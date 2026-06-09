// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import MetalKit
import simd

final class MetalRenderer: NSObject, MTKViewDelegate {
    private static let minimumPixelsPerUnit: Float = 0.000001
    private static let maxGridMarks = 40_000
    private static let maxGridLinesPerAxis = 400
    private static let maxGridIndexMagnitude = 1_000_000

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let textPipelineState: MTLRenderPipelineState
    private let textureLoader: MTKTextureLoader

    private var vertexBuffer: MTLBuffer?
    private var vertexCount = 0
    private var textSprites: [MetalTextSprite] = []
    private var gridVertexBuffer: MTLBuffer?
    private var gridVertexCount = 0
    private var gridCacheKey: GridCacheKey?
    private var bounds: DXFBounds?
    private weak var viewport: ViewportController?
    private var renderStyle = DXFRenderStyle()
    private var selectionState = MetalSelectionState()
    private var geometryCacheKey: MetalGeometryCacheKey?

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.clearColor = renderStyle.palette.background.metalClearColor
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        do {
            let library = try device.makeLibrary(source: MetalRenderer.shaderSource, options: nil)
            pipelineState = try MetalRenderer.makeLinePipelineState(device: device, library: library, pixelFormat: view.colorPixelFormat)
            textPipelineState = try MetalRenderer.makeTextPipelineState(device: device, library: library, pixelFormat: view.colorPixelFormat)
        } catch {
            return nil
        }

        super.init()
    }

    func update(
        scene: DXFScene,
        visibleLayers: Set<String>,
        viewport: ViewportController,
        renderStyle: DXFRenderStyle = DXFRenderStyle(),
        selectionState: MetalSelectionState = MetalSelectionState()
    ) {
        self.viewport = viewport
        self.renderStyle = renderStyle
        self.selectionState = selectionState

        let cacheKey = MetalGeometryCacheKey(
            sceneID: scene.id,
            visibleLayers: visibleLayers,
            palette: renderStyle.palette,
            textFontName: renderStyle.textFontName
        )
        guard cacheKey != geometryCacheKey else { return }

        let geometry = GeometryBuilder.build(scene: scene, visibleLayers: visibleLayers, palette: renderStyle.palette, textFontName: renderStyle.textFontName)
        bounds = geometry.bounds
        vertexCount = geometry.vertices.count
        textSprites = makeTextSprites(from: geometry.textSprites)
        geometryCacheKey = cacheKey

        guard !geometry.vertices.isEmpty else {
            vertexBuffer = nil
            return
        }

        vertexBuffer = geometry.vertices.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: [.storageModeShared])
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    func draw(in view: MTKView) {
        view.clearColor = renderStyle.palette.background.metalClearColor
        guard view.drawableSize.width.isFinite,
              view.drawableSize.height.isFinite,
              view.bounds.size.width.isFinite,
              view.bounds.size.height.isFinite,
              view.drawableSize.width > 0,
              view.drawableSize.height > 0,
              view.bounds.size.width > 0,
              view.bounds.size.height > 0 else {
            clearGridBuffer()
            return
        }

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        let renderContext = makeRenderContext(for: view.drawableSize, viewSize: view.bounds.size)

        if let renderContext {
            drawGrid(in: encoder, context: renderContext)
        }

        if let vertexBuffer, vertexCount > 0 {
            var uniforms = renderContext?.uniforms ?? fallbackUniforms(for: view.drawableSize)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }

        drawTextSprites(in: encoder, context: renderContext)

        if let renderContext {
            drawSelection(in: encoder, context: renderContext)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawGrid(in encoder: MTLRenderCommandEncoder, context: RenderContext) {
        guard renderStyle.showsGridMarks else {
            clearGridBuffer()
            return
        }

        updateGridBuffer(for: context)

        guard let gridVertexBuffer, gridVertexCount > 0 else { return }

        var uniforms = context.uniforms
        uniforms.lineThickness = 1.0
        encoder.setVertexBuffer(gridVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: gridVertexCount)
    }

    private func drawTextSprites(in encoder: MTLRenderCommandEncoder, context: RenderContext?) {
        guard let context, !textSprites.isEmpty else { return }

        var uniforms = context.uniforms
        encoder.setRenderPipelineState(textPipelineState)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)

        for sprite in textSprites {
            encoder.setVertexBuffer(sprite.vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(sprite.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: sprite.vertexCount)
        }

        encoder.setRenderPipelineState(pipelineState)
    }

    private func drawSelection(in encoder: MTLRenderCommandEncoder, context: RenderContext) {
        guard !selectionState.isEmpty else { return }

        let blue = SIMD4<Float>(0.11, 0.45, 1.0, 1.0)
        let blueHalo = SIMD4<Float>(0.11, 0.45, 1.0, 0.24)
        let purple = SIMD4<Float>(0.62, 0.34, 1.0, 1.0)
        let purpleHalo = SIMD4<Float>(0.62, 0.34, 1.0, 0.24)
        let white = SIMD4<Float>(1.0, 1.0, 1.0, 0.92)

        var haloSegments: [RenderVertex] = []
        var primarySegments: [RenderVertex] = []
        var hairlineSegments: [RenderVertex] = []
        var haloPoints: [RenderVertex] = []
        var primaryPoints: [RenderVertex] = []

        if let edge = selectionState.edge {
            appendSelectionSegment(start: edge.start, end: edge.end, color: blueHalo, vertices: &haloSegments)
            appendSelectionSegment(start: edge.start, end: edge.end, color: blue, vertices: &primarySegments)
            appendSelectionSegment(start: edge.start, end: edge.end, color: white, vertices: &hairlineSegments)
        }

        if let curve = selectionState.curve {
            appendSelectionPolyline(points: curve.points, isClosed: curve.isClosed, color: purpleHalo, vertices: &haloSegments)
            appendSelectionPolyline(points: curve.points, isClosed: curve.isClosed, color: purple, vertices: &primarySegments)
            appendSelectionPolyline(points: curve.points, isClosed: curve.isClosed, color: white, vertices: &hairlineSegments)

            for anchor in curve.anchors {
                appendSelectionPoint(anchor.point, color: purpleHalo, vertices: &haloPoints)
                appendAnchorMarker(
                    anchor,
                    color: purple,
                    hairlineColor: white,
                    pixelsPerUnit: context.pixelsPerUnit,
                    primarySegments: &primarySegments,
                    hairlineSegments: &hairlineSegments
                )
            }
        }

        for vertex in selectionState.vertices {
            appendSelectionPoint(vertex, color: blueHalo, vertices: &haloPoints)
            appendCircleMarker(
                center: vertex,
                radiusPixels: 8,
                color: blue,
                pixelsPerUnit: context.pixelsPerUnit,
                vertices: &primarySegments
            )
            appendCircleMarker(
                center: vertex,
                radiusPixels: 5,
                color: white,
                pixelsPerUnit: context.pixelsPerUnit,
                vertices: &hairlineSegments
            )
            appendSelectionPoint(vertex, color: blue, vertices: &primaryPoints)
        }

        drawSelectionVertices(haloPoints, thickness: 24, in: encoder, context: context)
        drawSelectionVertices(haloSegments, thickness: 10, in: encoder, context: context)
        drawSelectionVertices(primaryPoints, thickness: 4, in: encoder, context: context)
        drawSelectionVertices(primarySegments, thickness: 3, in: encoder, context: context)
        drawSelectionVertices(hairlineSegments, thickness: 1, in: encoder, context: context)
    }

    private func drawSelectionVertices(
        _ vertices: [RenderVertex],
        thickness: Float,
        in encoder: MTLRenderCommandEncoder,
        context: RenderContext
    ) {
        guard !vertices.isEmpty else { return }

        var uniforms = context.uniforms
        uniforms.lineThickness = thickness
        guard let buffer = vertices.withUnsafeBytes({ bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress, bytes.count > 0 else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: [.storageModeShared])
        }) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func appendSelectionPolyline(
        points: [SIMD2<Float>],
        isClosed: Bool,
        color: SIMD4<Float>,
        vertices: inout [RenderVertex]
    ) {
        guard points.count >= 2 else { return }

        for index in 0..<(points.count - 1) {
            appendSelectionSegment(start: points[index], end: points[index + 1], color: color, vertices: &vertices)
        }

        if isClosed,
           let first = points.first,
           let last = points.last,
           simd_distance(first, last) > 0.000001 {
            appendSelectionSegment(start: last, end: first, color: color, vertices: &vertices)
        }
    }

    private func appendSelectionSegment(
        start: SIMD2<Float>,
        end: SIMD2<Float>,
        color: SIMD4<Float>,
        vertices: inout [RenderVertex]
    ) {
        guard start.x.isFinite,
              start.y.isFinite,
              end.x.isFinite,
              end.y.isFinite,
              simd_distance(start, end) > 0.000001 else {
            return
        }

        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 1))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 1))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 1))
    }

    private func appendSelectionPoint(
        _ center: SIMD2<Float>,
        color: SIMD4<Float>,
        vertices: inout [RenderVertex]
    ) {
        guard center.x.isFinite, center.y.isFinite else { return }

        vertices.append(RenderVertex(start: center, end: center, color: color, side: -2, along: -1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: 2, along: -1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: 2, along: 1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: -2, along: -1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: 2, along: 1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: -2, along: 1))
    }

    private func appendAnchorMarker(
        _ anchor: MetalSelectionAnchor,
        color: SIMD4<Float>,
        hairlineColor: SIMD4<Float>,
        pixelsPerUnit: Float,
        primarySegments: inout [RenderVertex],
        hairlineSegments: inout [RenderVertex]
    ) {
        switch anchor.role {
        case .center:
            appendDiamondMarker(center: anchor.point, radiusPixels: 8, color: color, pixelsPerUnit: pixelsPerUnit, vertices: &primarySegments)
            appendDiamondMarker(center: anchor.point, radiusPixels: 5, color: hairlineColor, pixelsPerUnit: pixelsPerUnit, vertices: &hairlineSegments)
        case .endpoint:
            appendCircleMarker(center: anchor.point, radiusPixels: 7.5, color: color, pixelsPerUnit: pixelsPerUnit, vertices: &primarySegments)
            appendCircleMarker(center: anchor.point, radiusPixels: 5, color: hairlineColor, pixelsPerUnit: pixelsPerUnit, vertices: &hairlineSegments)
        case .controlPoint, .fitPoint:
            appendSquareMarker(center: anchor.point, radiusPixels: 7, color: color, pixelsPerUnit: pixelsPerUnit, vertices: &primarySegments)
            appendSquareMarker(center: anchor.point, radiusPixels: 4.5, color: hairlineColor, pixelsPerUnit: pixelsPerUnit, vertices: &hairlineSegments)
        }
    }

    private func appendCircleMarker(
        center: SIMD2<Float>,
        radiusPixels: Float,
        color: SIMD4<Float>,
        pixelsPerUnit: Float,
        vertices: inout [RenderVertex]
    ) {
        guard let radius = worldLength(forPixels: radiusPixels, pixelsPerUnit: pixelsPerUnit) else { return }

        let segmentCount = 28
        var previous = SIMD2(center.x + radius, center.y)
        for index in 1...segmentCount {
            let angle = Float(index) / Float(segmentCount) * 2 * .pi
            let next = SIMD2(center.x + cos(angle) * radius, center.y + sin(angle) * radius)
            appendSelectionSegment(start: previous, end: next, color: color, vertices: &vertices)
            previous = next
        }
    }

    private func appendDiamondMarker(
        center: SIMD2<Float>,
        radiusPixels: Float,
        color: SIMD4<Float>,
        pixelsPerUnit: Float,
        vertices: inout [RenderVertex]
    ) {
        guard let radius = worldLength(forPixels: radiusPixels, pixelsPerUnit: pixelsPerUnit) else { return }

        appendSelectionPolyline(
            points: [
                SIMD2(center.x, center.y + radius),
                SIMD2(center.x + radius, center.y),
                SIMD2(center.x, center.y - radius),
                SIMD2(center.x - radius, center.y),
            ],
            isClosed: true,
            color: color,
            vertices: &vertices
        )
    }

    private func appendSquareMarker(
        center: SIMD2<Float>,
        radiusPixels: Float,
        color: SIMD4<Float>,
        pixelsPerUnit: Float,
        vertices: inout [RenderVertex]
    ) {
        guard let radius = worldLength(forPixels: radiusPixels, pixelsPerUnit: pixelsPerUnit) else { return }

        appendSelectionPolyline(
            points: [
                SIMD2(center.x - radius, center.y - radius),
                SIMD2(center.x + radius, center.y - radius),
                SIMD2(center.x + radius, center.y + radius),
                SIMD2(center.x - radius, center.y + radius),
            ],
            isClosed: true,
            color: color,
            vertices: &vertices
        )
    }

    private func worldLength(forPixels pixels: Float, pixelsPerUnit: Float) -> Float? {
        guard pixels.isFinite,
              pixels > 0,
              pixelsPerUnit.isFinite,
              pixelsPerUnit > Self.minimumPixelsPerUnit else {
            return nil
        }

        let length = pixels / pixelsPerUnit
        return length.isFinite && length > 0 ? length : nil
    }

    private func makeTextSprites(from sprites: [RenderTextSprite]) -> [MetalTextSprite] {
        sprites.compactMap { sprite in
            guard let texture = try? textureLoader.newTexture(
                cgImage: sprite.image,
                options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                ]
            ) else {
                return nil
            }

            guard let vertexBuffer = sprite.vertices.withUnsafeBytes({ bytes -> MTLBuffer? in
                guard let baseAddress = bytes.baseAddress, bytes.count > 0 else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: [.storageModeShared])
            }) else {
                return nil
            }

            return MetalTextSprite(texture: texture, vertexBuffer: vertexBuffer, vertexCount: sprite.vertices.count)
        }
    }

    private func updateGridBuffer(for context: RenderContext) {
        let visible = context.visibleWorldBounds
        let spacing = AdaptiveGrid.spacing(forPixelsPerUnit: context.pixelsPerUnit)
        guard spacing.isFinite,
              spacing > 0,
              context.pixelsPerUnit.isFinite,
              context.pixelsPerUnit > Self.minimumPixelsPerUnit,
              visible.min.x.isFinite,
              visible.min.y.isFinite,
              visible.max.x.isFinite,
              visible.max.y.isFinite else {
            clearGridBuffer()
            return
        }

        let halfMarkWorld = AdaptiveGrid.markHalfLengthPixels / context.pixelsPerUnit
        guard halfMarkWorld.isFinite,
              halfMarkWorld > 0,
              let minXIndex = gridIndex(for: visible.min.x, spacing: spacing, roundedBy: { $0.rounded(.down) }, offset: -1),
              let maxXIndex = gridIndex(for: visible.max.x, spacing: spacing, roundedBy: { $0.rounded(.up) }, offset: 1),
              let minYIndex = gridIndex(for: visible.min.y, spacing: spacing, roundedBy: { $0.rounded(.down) }, offset: -1),
              let maxYIndex = gridIndex(for: visible.max.y, spacing: spacing, roundedBy: { $0.rounded(.up) }, offset: 1) else {
            clearGridBuffer()
            return
        }
        let color = gridColor()

        let cacheKey = GridCacheKey(
            spacing: spacing,
            halfMarkWorld: halfMarkWorld,
            minXIndex: minXIndex,
            maxXIndex: maxXIndex,
            minYIndex: minYIndex,
            maxYIndex: maxYIndex,
            color: color
        )

        guard cacheKey != gridCacheKey else { return }

        let xCount64 = Int64(maxXIndex) - Int64(minXIndex) + 1
        let yCount64 = Int64(maxYIndex) - Int64(minYIndex) + 1
        guard xCount64 > 0,
              yCount64 > 0,
              xCount64 <= Int64(Self.maxGridLinesPerAxis),
              yCount64 <= Int64(Self.maxGridLinesPerAxis),
              xCount64 * yCount64 <= Int64(Self.maxGridMarks) else {
            clearGridBuffer(resetCache: false)
            gridCacheKey = cacheKey
            return
        }

        let xCount = Int(xCount64)
        let yCount = Int(yCount64)
        var vertices: [RenderVertex] = []
        vertices.reserveCapacity(xCount * yCount * 12)

        for xIndex in minXIndex...maxXIndex {
            let x = Float(xIndex) * spacing
            for yIndex in minYIndex...maxYIndex {
                let y = Float(yIndex) * spacing
                let center = SIMD2(x, y)
                appendGridSegment(
                    start: SIMD2(center.x - halfMarkWorld, center.y),
                    end: SIMD2(center.x + halfMarkWorld, center.y),
                    color: color,
                    vertices: &vertices
                )
                appendGridSegment(
                    start: SIMD2(center.x, center.y - halfMarkWorld),
                    end: SIMD2(center.x, center.y + halfMarkWorld),
                    color: color,
                    vertices: &vertices
                )
            }
        }

        gridVertexCount = vertices.count
        gridVertexBuffer = vertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress, bytes.count > 0 else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: [.storageModeShared])
        }
        gridCacheKey = cacheKey
    }

    private func clearGridBuffer(resetCache: Bool = true) {
        gridVertexBuffer = nil
        gridVertexCount = 0
        if resetCache {
            gridCacheKey = nil
        }
    }

    private func gridIndex(
        for value: Float,
        spacing: Float,
        roundedBy: (Double) -> Double,
        offset: Int
    ) -> Int? {
        guard value.isFinite, spacing.isFinite, spacing > 0 else { return nil }

        let rawIndex = Double(value / spacing)
        guard rawIndex.isFinite else { return nil }

        let adjustedIndex = roundedBy(rawIndex) + Double(offset)
        guard adjustedIndex.isFinite,
              adjustedIndex >= -Double(Self.maxGridIndexMagnitude),
              adjustedIndex <= Double(Self.maxGridIndexMagnitude) else {
            return nil
        }

        return Int(adjustedIndex)
    }

    private func gridColor() -> SIMD4<Float> {
        let background = renderStyle.palette.background
        let grid = renderStyle.palette.grid
        let opacity = min(max(grid.alpha * 0.72, 0), 1)
        let red = background.red * (1 - opacity) + grid.red * opacity
        let green = background.green * (1 - opacity) + grid.green * opacity
        let blue = background.blue * (1 - opacity) + grid.blue * opacity
        return SIMD4(red, green, blue, 1)
    }

    private func appendGridSegment(
        start: SIMD2<Float>,
        end: SIMD2<Float>,
        color: SIMD4<Float>,
        vertices: inout [RenderVertex]
    ) {
        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 1))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 1))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 1))
    }

    private func makeRenderContext(for drawableSize: CGSize, viewSize: CGSize) -> RenderContext? {
        guard let bounds,
              drawableSize.width.isFinite,
              drawableSize.height.isFinite,
              viewSize.width.isFinite,
              viewSize.height.isFinite,
              drawableSize.width > 0,
              drawableSize.height > 0,
              viewSize.width > 0,
              viewSize.height > 0,
              bounds.min.x.isFinite,
              bounds.min.y.isFinite,
              bounds.max.x.isFinite,
              bounds.max.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0,
              bounds.center.x.isFinite,
              bounds.center.y.isFinite else {
            return nil
        }

        let zoom = viewport?.zoom ?? 1.0
        let pan = viewport?.pan ?? .zero
        let drawableWidth = Float(drawableSize.width)
        let drawableHeight = Float(drawableSize.height)
        guard zoom.isFinite,
              zoom > 0,
              pan.x.isFinite,
              pan.y.isFinite,
              drawableWidth.isFinite,
              drawableHeight.isFinite,
              drawableWidth > 0,
              drawableHeight > 0 else {
            return nil
        }

        let insets = renderStyle.contentInsets.scaled(from: viewSize, to: drawableSize)
        guard insets.top.isFinite,
              insets.leading.isFinite,
              insets.bottom.isFinite,
              insets.trailing.isFinite else {
            return nil
        }

        let leading = min(max(insets.leading, 0), drawableWidth - 1)
        let trailing = min(max(insets.trailing, 0), drawableWidth - leading - 1)
        let top = min(max(insets.top, 0), drawableHeight - 1)
        let bottom = min(max(insets.bottom, 0), drawableHeight - top - 1)
        let contentWidth = max(drawableWidth - leading - trailing, 1)
        let contentHeight = max(drawableHeight - top - bottom, 1)
        let contentCenterX = leading + contentWidth * 0.5
        let contentCenterY = top + contentHeight * 0.5
        let fitOffset = SIMD2(
            contentCenterX / drawableWidth * 2.0 - 1.0,
            1.0 - contentCenterY / drawableHeight * 2.0
        )
        let pixelsPerUnit = min(contentWidth / bounds.width, contentHeight / bounds.height) * 0.92 * zoom
        let scaleX = 2.0 * pixelsPerUnit / drawableWidth
        let scaleY = 2.0 * pixelsPerUnit / drawableHeight
        let center = bounds.center
        let translateX = -center.x * scaleX + fitOffset.x + pan.x
        let translateY = -center.y * scaleY + fitOffset.y + pan.y
        guard pixelsPerUnit.isFinite,
              pixelsPerUnit > Self.minimumPixelsPerUnit,
              scaleX.isFinite,
              scaleY.isFinite,
              scaleX > 0,
              scaleY > 0,
              fitOffset.x.isFinite,
              fitOffset.y.isFinite,
              translateX.isFinite,
              translateY.isFinite else {
            return nil
        }

        let transform = simd_float4x4(
            SIMD4(scaleX, 0, 0, 0),
            SIMD4(0, scaleY, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(translateX, translateY, 0, 1)
        )

        let uniforms = RenderUniforms(
            transform: transform,
            viewportSize: SIMD2(max(drawableWidth, 1), max(drawableHeight, 1)),
            lineThickness: renderStyle.lineThickness,
            padding: 0
        )

        return RenderContext(
            bounds: bounds,
            uniforms: uniforms,
            pixelsPerUnit: pixelsPerUnit,
            scaleX: scaleX,
            scaleY: scaleY,
            fitOffset: fitOffset,
            pan: pan
        )
    }

    private func fallbackUniforms(for drawableSize: CGSize) -> RenderUniforms {
        let drawableWidth = Float(drawableSize.width)
        let drawableHeight = Float(drawableSize.height)
        let viewportWidth = drawableWidth.isFinite && drawableWidth > 0 ? drawableWidth : 1
        let viewportHeight = drawableHeight.isFinite && drawableHeight > 0 ? drawableHeight : 1

        return RenderUniforms(
            transform: matrix_identity_float4x4,
            viewportSize: SIMD2(viewportWidth, viewportHeight),
            lineThickness: renderStyle.lineThickness,
            padding: 0
        )
    }

    private static func makeLinePipelineState(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = MemoryLayout<RenderVertex>.offset(of: \.start) ?? 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<RenderVertex>.offset(of: \.end) ?? MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<RenderVertex>.offset(of: \.color) ?? MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[3].format = .float
        vertexDescriptor.attributes[3].offset = MemoryLayout<RenderVertex>.offset(of: \.side) ?? MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.attributes[4].format = .float
        vertexDescriptor.attributes[4].offset = MemoryLayout<RenderVertex>.offset(of: \.along) ?? MemoryLayout<SIMD2<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride + MemoryLayout<Float>.stride
        vertexDescriptor.attributes[4].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<RenderVertex>.stride
        descriptor.vertexDescriptor = vertexDescriptor

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeTextPipelineState(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "text_vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "text_fragment_main")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = MemoryLayout<RenderTextVertex>.offset(of: \.position) ?? 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<RenderTextVertex>.offset(of: \.texCoord) ?? MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<RenderTextVertex>.offset(of: \.color) ?? MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<RenderTextVertex>.stride
        descriptor.vertexDescriptor = vertexDescriptor

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 start [[attribute(0)]];
        float2 end [[attribute(1)]];
        float4 color [[attribute(2)]];
        float side [[attribute(3)]];
        float along [[attribute(4)]];
    };

    struct Uniforms {
        float4x4 transform;
        float2 viewportSize;
        float lineThickness;
        float padding;
    };

    struct VertexOut {
        float4 position [[position]];
        float4 color;
        float2 pointCoord;
        float isPoint;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(1)]]) {
        float2 start = (uniforms.transform * float4(in.start, 0.0, 1.0)).xy;
        float2 end = (uniforms.transform * float4(in.end, 0.0, 1.0)).xy;
        bool isPoint = abs(in.side) > 1.5;
        float2 position;
        float2 pointCoord = float2(0.0);
        if (isPoint) {
            pointCoord = float2(in.side * 0.5, in.along);
            float2 offset = pointCoord * uniforms.lineThickness * 0.5 * float2(2.0 / uniforms.viewportSize.x,
                                                                               2.0 / uniforms.viewportSize.y);
            position = start + offset;
        } else {
            float2 directionPixels = (end - start) * uniforms.viewportSize;
            float lengthPixels = max(length(directionPixels), 0.0001);
            float2 tangent = directionPixels / lengthPixels;
            float2 normal = float2(-tangent.y, tangent.x);
            float2 offset = normal * in.side * uniforms.lineThickness * 0.5 * float2(2.0 / uniforms.viewportSize.x,
                                                                                     2.0 / uniforms.viewportSize.y);
            position = mix(start, end, in.along) + offset;
        }

        VertexOut out;
        out.position = float4(position, 0.0, 1.0);
        out.color = in.color;
        out.pointCoord = pointCoord;
        out.isPoint = isPoint ? 1.0 : 0.0;
        return out;
    }

    fragment half4 fragment_main(VertexOut in [[stage_in]]) {
        if (in.isPoint > 0.5 && dot(in.pointCoord, in.pointCoord) > 1.0) {
            discard_fragment();
        }
        return half4(in.color);
    }

    struct TextVertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
        float4 color [[attribute(2)]];
    };

    struct TextVertexOut {
        float4 position [[position]];
        float2 texCoord;
        float4 color;
    };

    vertex TextVertexOut text_vertex_main(TextVertexIn in [[stage_in]],
                                          constant Uniforms& uniforms [[buffer(1)]]) {
        TextVertexOut out;
        out.position = uniforms.transform * float4(in.position, 0.0, 1.0);
        out.texCoord = in.texCoord;
        out.color = in.color;
        return out;
    }

    fragment half4 text_fragment_main(TextVertexOut in [[stage_in]],
                                      texture2d<float> textTexture [[texture(0)]]) {
        constexpr sampler textSampler(address::clamp_to_edge, filter::linear);
        float alpha = textTexture.sample(textSampler, in.texCoord).a * in.color.a;
        return half4(half3(in.color.rgb), half(alpha));
    }
    """
}

private struct MetalTextSprite {
    let texture: MTLTexture
    let vertexBuffer: MTLBuffer
    let vertexCount: Int
}

struct MetalSelectionState {
    var vertices: [SIMD2<Float>] = []
    var edge: MetalSelectionEdge?
    var curve: MetalSelectionCurve?

    var isEmpty: Bool {
        vertices.isEmpty && edge == nil && curve == nil
    }
}

struct MetalSelectionEdge {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
}

struct MetalSelectionCurve {
    var points: [SIMD2<Float>]
    var isClosed: Bool
    var anchors: [MetalSelectionAnchor]
}

struct MetalSelectionAnchor {
    var point: SIMD2<Float>
    var role: MetalSelectionAnchorRole
}

enum MetalSelectionAnchorRole {
    case center
    case endpoint
    case controlPoint
    case fitPoint
}

private struct RenderUniforms {
    var transform: simd_float4x4
    var viewportSize: SIMD2<Float>
    var lineThickness: Float
    var padding: Float
}

private struct RenderContext {
    let bounds: DXFBounds
    let uniforms: RenderUniforms
    let pixelsPerUnit: Float
    let scaleX: Float
    let scaleY: Float
    let fitOffset: SIMD2<Float>
    let pan: SIMD2<Float>

    var visibleWorldBounds: DXFBounds {
        let corners = [
            worldPoint(forClip: SIMD2<Float>(-1, -1)),
            worldPoint(forClip: SIMD2<Float>(-1, 1)),
            worldPoint(forClip: SIMD2<Float>(1, -1)),
            worldPoint(forClip: SIMD2<Float>(1, 1)),
        ]

        var worldBounds = DXFBounds(point: corners[0])
        for corner in corners.dropFirst() {
            worldBounds.include(corner)
        }
        return worldBounds
    }

    private func worldPoint(forClip clip: SIMD2<Float>) -> SIMD2<Float> {
        let center = bounds.center
        return SIMD2(
            (clip.x - fitOffset.x - pan.x) / scaleX + center.x,
            (clip.y - fitOffset.y - pan.y) / scaleY + center.y
        )
    }
}

private struct GridCacheKey: Equatable {
    let spacing: UInt32
    let halfMarkWorld: UInt32
    let minXIndex: Int
    let maxXIndex: Int
    let minYIndex: Int
    let maxYIndex: Int
    let red: UInt32
    let green: UInt32
    let blue: UInt32
    let alpha: UInt32

    init(
        spacing: Float,
        halfMarkWorld: Float,
        minXIndex: Int,
        maxXIndex: Int,
        minYIndex: Int,
        maxYIndex: Int,
        color: SIMD4<Float>
    ) {
        self.spacing = spacing.bitPattern
        self.halfMarkWorld = halfMarkWorld.bitPattern
        self.minXIndex = minXIndex
        self.maxXIndex = maxXIndex
        self.minYIndex = minYIndex
        self.maxYIndex = maxYIndex
        red = color.x.bitPattern
        green = color.y.bitPattern
        blue = color.z.bitPattern
        alpha = color.w.bitPattern
    }
}

private struct MetalGeometryCacheKey: Equatable {
    let sceneID: UUID
    let visibleLayers: Set<String>
    let palette: DXFRenderPalette
    let textFontName: String
}

private extension RenderColor {
    var metalClearColor: MTLClearColor {
        MTLClearColor(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }
}
