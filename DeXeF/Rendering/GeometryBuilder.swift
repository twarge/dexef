// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import CoreText
import Foundation
import simd

struct RenderVertex {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var color: SIMD4<Float>
    var side: Float
    var along: Float
}

struct RenderSegment {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var color: SIMD4<Float>
    var isSelectable: Bool
    var isCurveApproximation: Bool
}

struct RenderPoint {
    var center: SIMD2<Float>
    var color: SIMD4<Float>
    var isSelectable: Bool
}

struct RenderFillPolygon {
    let boundaryLoops: [[SIMD2<Float>]]
    let color: SIMD4<Float>
}

struct RenderTextVertex {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
    var color: SIMD4<Float>
}

struct RenderTextSprite {
    let image: CGImage
    let vertices: [RenderTextVertex]
}

struct RenderGeometry {
    let vertices: [RenderVertex]
    let segments: [RenderSegment]
    let points: [RenderPoint]
    let filledPolygons: [RenderFillPolygon]
    let textSprites: [RenderTextSprite]
    let bounds: DXFBounds?
}

enum GeometryBuilder {
    static func build(
        scene: DXFScene,
        visibleLayers: Set<String>,
        palette: DXFRenderPalette = .standardDark,
        includeTextFills: Bool = true,
        textFontName: String = DXFRenderStyle.defaultTextFontName
    ) -> RenderGeometry {
        let layerColors = Dictionary(uniqueKeysWithValues: scene.layers.map { ($0.name, $0.colorIndex) })
        var vertices: [RenderVertex] = []
        var segments: [RenderSegment] = []
        var points: [RenderPoint] = []
        var filledPolygons: [RenderFillPolygon] = []
        var textSprites: [RenderTextSprite] = []
        var bounds: DXFBounds?

        for primitive in scene.primitives where visibleLayers.contains(primitive.layerName) {
            let color = primitive.trueColor ?? palette.color(for: primitive.colorIndex ?? layerColors[primitive.layerName] ?? nil)
            append(
                primitive: primitive,
                color: color,
                includeTextFills: includeTextFills,
                textFontName: textFontName,
                vertices: &vertices,
                segments: &segments,
                points: &points,
                filledPolygons: &filledPolygons,
                textSprites: &textSprites,
                bounds: &bounds
            )
        }

        return RenderGeometry(vertices: vertices, segments: segments, points: points, filledPolygons: filledPolygons, textSprites: textSprites, bounds: bounds)
    }

    private static func append(
        primitive: DXFPrimitive,
        color: SIMD4<Float>,
        includeTextFills: Bool,
        textFontName: String,
        vertices: inout [RenderVertex],
        segments: inout [RenderSegment],
        points: inout [RenderPoint],
        filledPolygons: inout [RenderFillPolygon],
        textSprites: inout [RenderTextSprite],
        bounds: inout DXFBounds?
    ) {
        switch primitive.kind {
        case let .point(center):
            appendPoint(center, color: color, isSelectable: primitive.isSelectable, vertices: &vertices, points: &points, bounds: &bounds)

        case let .line(start, end):
            appendSegment(start, end, color: color, isSelectable: primitive.isSelectable, vertices: &vertices, segments: &segments, bounds: &bounds)

        case let .polyline(points, isClosed):
            guard points.count >= 2 else { return }
            for index in 0..<(points.count - 1) {
                appendSegment(points[index], points[index + 1], color: color, isSelectable: primitive.isSelectable, vertices: &vertices, segments: &segments, bounds: &bounds)
            }
            if isClosed,
               let first = points.first,
               let last = points.last,
               simd_distance(first, last) > closureTolerance(for: points) {
                appendSegment(last, first, color: color, isSelectable: primitive.isSelectable, vertices: &vertices, segments: &segments, bounds: &bounds)
            }

        case let .curve(curve):
            appendCurve(curve.points, isClosed: curve.isClosed, color: color, isSelectable: primitive.isSelectable, vertices: &vertices, segments: &segments, bounds: &bounds)

        case let .hatchFill(boundaryLoops):
            appendFill(boundaryLoops: boundaryLoops, color: color, vertices: &vertices, filledPolygons: &filledPolygons, bounds: &bounds)

        case let .circle(center, radius):
            appendArc(center: center, radius: radius, startAngle: 0, endAngle: 360, color: color, isSelectable: primitive.isSelectable, vertices: &vertices, segments: &segments, bounds: &bounds)

        case let .arc(center, radius, startAngle, endAngle):
            appendArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, color: color, isSelectable: primitive.isSelectable, vertices: &vertices, segments: &segments, bounds: &bounds)

        case let .text(text):
            appendText(text, color: color, includeFill: includeTextFills, textFontName: textFontName, vertices: &vertices, segments: &segments, textSprites: &textSprites, bounds: &bounds)
        }
    }

    private static func appendText(
        _ text: DXFText,
        color: SIMD4<Float>,
        includeFill: Bool,
        textFontName: String,
        vertices: inout [RenderVertex],
        segments: inout [RenderSegment],
        textSprites: inout [RenderTextSprite],
        bounds: inout DXFBounds?
    ) {
        let content = text.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, text.height > 0 else { return }

        if includeFill, let sprite = textSprite(for: text, color: color, textFontName: textFontName) {
            textSprites.append(sprite)
            for vertex in sprite.vertices {
                include(vertex.position, in: &bounds)
            }
        } else {
            for (start, end) in textSegments(for: text, textFontName: textFontName) {
                appendSegment(start, end, color: color, isSelectable: false, vertices: &vertices, segments: &segments, bounds: &bounds)
            }
        }
    }

    private static func appendArc(
        center: SIMD2<Float>,
        radius: Float,
        startAngle: Float,
        endAngle: Float,
        color: SIMD4<Float>,
        isSelectable: Bool,
        vertices: inout [RenderVertex],
        segments: inout [RenderSegment],
        bounds: inout DXFBounds?
    ) {
        let sweep = normalizedSweep(from: startAngle, to: endAngle)
        let segmentCount = max(12, min(192, Int(ceil(abs(sweep) / 8.0))))
        var previous = point(onCircleAt: startAngle, center: center, radius: radius)

        for step in 1...segmentCount {
            let t = Float(step) / Float(segmentCount)
            let angle = startAngle + sweep * t
            let next = point(onCircleAt: angle, center: center, radius: radius)
            appendSegment(previous, next, color: color, isSelectable: isSelectable, isCurveApproximation: true, vertices: &vertices, segments: &segments, bounds: &bounds)
            previous = next
        }
    }

    private static func appendCurve(
        _ points: [SIMD2<Float>],
        isClosed: Bool,
        color: SIMD4<Float>,
        isSelectable: Bool,
        vertices: inout [RenderVertex],
        segments: inout [RenderSegment],
        bounds: inout DXFBounds?
    ) {
        guard points.count >= 2 else {
            for point in points {
                include(point, in: &bounds)
            }
            return
        }

        for index in 0..<(points.count - 1) {
            appendSegment(points[index], points[index + 1], color: color, isSelectable: isSelectable, isCurveApproximation: true, vertices: &vertices, segments: &segments, bounds: &bounds)
        }
        if isClosed,
           let first = points.first,
           let last = points.last,
           simd_distance(first, last) > closureTolerance(for: points) {
            appendSegment(last, first, color: color, isSelectable: isSelectable, isCurveApproximation: true, vertices: &vertices, segments: &segments, bounds: &bounds)
        }
    }

    private static func appendSegment(
        _ start: SIMD2<Float>,
        _ end: SIMD2<Float>,
        color: SIMD4<Float>,
        isSelectable: Bool,
        isCurveApproximation: Bool = false,
        vertices: inout [RenderVertex],
        segments: inout [RenderSegment],
        bounds: inout DXFBounds?
    ) {
        guard start.x.isFinite,
              start.y.isFinite,
              end.x.isFinite,
              end.y.isFinite,
              simd_distance(start, end) > 0.000001 else {
            include(start, in: &bounds)
            include(end, in: &bounds)
            return
        }

        segments.append(RenderSegment(start: start, end: end, color: color, isSelectable: isSelectable, isCurveApproximation: isCurveApproximation))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 1))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 0))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: 1, along: 1))
        vertices.append(RenderVertex(start: start, end: end, color: color, side: -1, along: 1))
        include(start, in: &bounds)
        include(end, in: &bounds)
    }

    private static func appendPoint(
        _ center: SIMD2<Float>,
        color: SIMD4<Float>,
        isSelectable: Bool,
        vertices: inout [RenderVertex],
        points: inout [RenderPoint],
        bounds: inout DXFBounds?
    ) {
        points.append(RenderPoint(center: center, color: color, isSelectable: isSelectable))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: -2, along: -1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: 2, along: -1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: 2, along: 1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: -2, along: -1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: 2, along: 1))
        vertices.append(RenderVertex(start: center, end: center, color: color, side: -2, along: 1))
        include(center, in: &bounds)
    }

    private static func appendFill(
        boundaryLoops: [[SIMD2<Float>]],
        color: SIMD4<Float>,
        vertices: inout [RenderVertex],
        filledPolygons: inout [RenderFillPolygon],
        bounds: inout DXFBounds?
    ) {
        let loops = boundaryLoops.compactMap(cleanFillLoop)
        guard !loops.isEmpty else { return }

        filledPolygons.append(RenderFillPolygon(boundaryLoops: loops, color: color))

        for loop in loops {
            for point in loop {
                include(point, in: &bounds)
            }

            for triangle in triangulateSimplePolygon(loop) {
                appendFillTriangle(triangle.0, triangle.1, triangle.2, color: color, vertices: &vertices)
            }
        }
    }

    private static func appendFillTriangle(
        _ first: SIMD2<Float>,
        _ second: SIMD2<Float>,
        _ third: SIMD2<Float>,
        color: SIMD4<Float>,
        vertices: inout [RenderVertex]
    ) {
        vertices.append(RenderVertex(start: first, end: first, color: color, side: 0, along: 0))
        vertices.append(RenderVertex(start: second, end: second, color: color, side: 0, along: 0))
        vertices.append(RenderVertex(start: third, end: third, color: color, side: 0, along: 0))
    }

    private static func cleanFillLoop(_ rawPoints: [SIMD2<Float>]) -> [SIMD2<Float>]? {
        let finitePoints = rawPoints.filter { $0.x.isFinite && $0.y.isFinite }
        guard finitePoints.count >= 3 else { return nil }

        let tolerance = closureTolerance(for: finitePoints)
        var points: [SIMD2<Float>] = []
        for point in finitePoints {
            if let last = points.last, simd_distance(last, point) <= tolerance {
                continue
            }
            points.append(point)
        }

        if points.count >= 2,
           let first = points.first,
           let last = points.last,
           simd_distance(first, last) <= tolerance {
            points.removeLast()
        }

        var didRemove = true
        while didRemove, points.count >= 3 {
            didRemove = false
            for index in 0..<points.count {
                let previous = points[(index - 1 + points.count) % points.count]
                let current = points[index]
                let next = points[(index + 1) % points.count]
                if abs(cross(current - previous, next - current)) <= tolerance * tolerance {
                    points.remove(at: index)
                    didRemove = true
                    break
                }
            }
        }

        guard points.count >= 3, abs(signedArea(points)) > tolerance * tolerance else { return nil }
        return points
    }

    private static func triangulateSimplePolygon(_ rawPoints: [SIMD2<Float>]) -> [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] {
        guard var points = cleanFillLoop(rawPoints) else { return [] }
        if signedArea(points) < 0 {
            points.reverse()
        }

        var indices = Array(points.indices)
        var triangles: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
        let maxIterations = max(indices.count * indices.count, 1)
        var iterations = 0

        while indices.count > 3 && iterations < maxIterations {
            iterations += 1
            var didClip = false

            for localIndex in indices.indices {
                let previousIndex = indices[(localIndex - 1 + indices.count) % indices.count]
                let currentIndex = indices[localIndex]
                let nextIndex = indices[(localIndex + 1) % indices.count]
                let previous = points[previousIndex]
                let current = points[currentIndex]
                let next = points[nextIndex]

                guard isConvex(previous, current, next) else { continue }

                let containsPoint = indices.contains { testIndex in
                    guard testIndex != previousIndex,
                          testIndex != currentIndex,
                          testIndex != nextIndex else {
                        return false
                    }
                    return point(points[testIndex], isInsideTriangle: (previous, current, next))
                }

                if !containsPoint {
                    triangles.append((previous, current, next))
                    indices.remove(at: localIndex)
                    didClip = true
                    break
                }
            }

            if !didClip {
                break
            }
        }

        if indices.count == 3 {
            triangles.append((points[indices[0]], points[indices[1]], points[indices[2]]))
        } else if triangles.isEmpty, points.count >= 3 {
            let anchor = points[0]
            for index in 1..<(points.count - 1) {
                triangles.append((anchor, points[index], points[index + 1]))
            }
        }

        return triangles
    }

    private static func signedArea(_ points: [SIMD2<Float>]) -> Float {
        guard points.count >= 3 else { return 0 }
        var area: Float = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            area += points[index].x * next.y - next.x * points[index].y
        }
        return area * 0.5
    }

    private static func isConvex(_ previous: SIMD2<Float>, _ current: SIMD2<Float>, _ next: SIMD2<Float>) -> Bool {
        cross(current - previous, next - current) > 0.0000001
    }

    private static func point(
        _ point: SIMD2<Float>,
        isInsideTriangle triangle: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    ) -> Bool {
        let (first, second, third) = triangle
        let area = cross(second - first, third - first)
        guard abs(area) > 0.0000001 else { return false }

        let firstWeight = cross(second - point, third - point) / area
        let secondWeight = cross(third - point, first - point) / area
        let thirdWeight = cross(first - point, second - point) / area
        let tolerance: Float = -0.00001
        return firstWeight >= tolerance && secondWeight >= tolerance && thirdWeight >= tolerance
    }

    private static func cross(_ first: SIMD2<Float>, _ second: SIMD2<Float>) -> Float {
        first.x * second.y - first.y * second.x
    }

    private static func include(_ point: SIMD2<Float>, in bounds: inout DXFBounds?) {
        if bounds == nil {
            bounds = DXFBounds(point: point)
        } else {
            bounds?.include(point)
        }
    }

    private static func closureTolerance(for points: [SIMD2<Float>]) -> Float {
        guard var minPoint = points.first,
              var maxPoint = points.first else {
            return 0.0001
        }

        for point in points.dropFirst() {
            minPoint = SIMD2(min(minPoint.x, point.x), min(minPoint.y, point.y))
            maxPoint = SIMD2(max(maxPoint.x, point.x), max(maxPoint.y, point.y))
        }

        let span = max(maxPoint.x - minPoint.x, maxPoint.y - minPoint.y)
        return max(span * 0.00001, 0.0001)
    }

    private static func point(onCircleAt angle: Float, center: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        let radians = angle * .pi / 180.0
        return SIMD2(center.x + cos(radians) * radius, center.y + sin(radians) * radius)
    }

    private static func textSegments(for text: DXFText, textFontName: String) -> [(SIMD2<Float>, SIMD2<Float>)] {
        let lines = renderLines(for: text)
        guard !lines.isEmpty else { return [] }

        let metricsFont = textFont(named: textFontName, size: CGFloat(text.height), isBold: text.isBold)
        let radians = text.rotation * .pi / 180.0
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        var allSegments: [(SIMD2<Float>, SIMD2<Float>)] = []
        let verticalOffset = textVerticalOffset(anchor: text.verticalAnchor, font: metricsFont, lineCount: lines.count, fontScale: 1)

        for (lineIndex, line) in lines.enumerated() {
            let font = textFont(named: textFontName, size: CGFloat(text.height), isBold: line.isBold)
            let attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font]
            let attributed = NSAttributedString(string: line.content, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let lineWidth = Float(CTLineGetTypographicBounds(ctLine, nil, nil, nil)) * text.widthFactor
            let horizontalOffset = textHorizontalOffset(anchor: text.horizontalAnchor, width: lineWidth)
            let runs = CTLineGetGlyphRuns(ctLine) as! [CTRun]
            let baselineOffset = Float(lineIndex) * text.height * 1.35

            for run in runs {
                let glyphCount = CTRunGetGlyphCount(run)
                guard glyphCount > 0 else { continue }

                var glyphs = Array(repeating: CGGlyph(), count: glyphCount)
                var positions = Array(repeating: CGPoint.zero, count: glyphCount)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)

                for index in 0..<glyphCount {
                    guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                    let glyphOrigin = positions[index]
                    let flattened = flattenedSegments(from: glyphPath)

                    for (start, end) in flattened {
                        let localStart = SIMD2(
                            (Float(glyphOrigin.x) + start.x) * text.widthFactor + horizontalOffset,
                            start.y - baselineOffset + verticalOffset
                        )
                        let localEnd = SIMD2(
                            (Float(glyphOrigin.x) + end.x) * text.widthFactor + horizontalOffset,
                            end.y - baselineOffset + verticalOffset
                        )
                        allSegments.append((
                            transformTextPoint(localStart, insertion: text.insertion, cosValue: cosValue, sinValue: sinValue),
                            transformTextPoint(localEnd, insertion: text.insertion, cosValue: cosValue, sinValue: sinValue)
                        ))
                    }
                }
            }
        }

        return allSegments
    }

    private static func textSprite(for text: DXFText, color: SIMD4<Float>, textFontName: String) -> RenderTextSprite? {
        let lines = renderLines(for: text)
        guard !lines.isEmpty else { return nil }

        let fontSizePixels: CGFloat = 128
        let paddingPixels: CGFloat = 6
        let fonts = lines.map { textFont(named: textFontName, size: fontSizePixels, isBold: $0.isBold) }
        let ctLines = zip(lines, fonts).map { line, font in
            let attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font]
            return CTLineCreateWithAttributedString(NSAttributedString(string: line.content, attributes: attributes))
        }
        let lineWidthsPixels = ctLines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        let ascentPixels = fonts.map(CTFontGetAscent).max() ?? fontSizePixels
        let descentPixels = fonts.map(CTFontGetDescent).max() ?? 0
        let lineAdvancePixels = fontSizePixels * 1.35

        var inkBoundsPixels: CGRect?
        for (index, line) in ctLines.enumerated() {
            var lineBounds = CTLineGetImageBounds(line, nil)
            if lineBounds.isNull || lineBounds.isEmpty {
                lineBounds = CGRect(x: 0, y: -descentPixels, width: max(lineWidthsPixels[index], 1), height: ascentPixels + descentPixels)
            }

            lineBounds = lineBounds.offsetBy(
                dx: textHorizontalOffset(anchor: text.horizontalAnchor, width: lineWidthsPixels[index]),
                dy: -lineAdvancePixels * CGFloat(index)
            )
            inkBoundsPixels = inkBoundsPixels.map { $0.union(lineBounds) } ?? lineBounds
        }

        guard let inkBoundsPixels else { return nil }

        let textureMinX = floor(inkBoundsPixels.minX - paddingPixels)
        let textureMinY = floor(inkBoundsPixels.minY - paddingPixels)
        let imageWidth = max(1, Int(ceil(inkBoundsPixels.maxX + paddingPixels) - textureMinX))
        let imageHeight = max(1, Int(ceil(inkBoundsPixels.maxY + paddingPixels) - textureMinY))
        let textureMaxX = textureMinX + CGFloat(imageWidth)
        let textureMaxY = textureMinY + CGFloat(imageHeight)

        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.textMatrix = .identity

        for (index, line) in ctLines.enumerated() {
            let baselinePixels = -lineAdvancePixels * CGFloat(index)
            context.textPosition = CGPoint(
                x: textHorizontalOffset(anchor: text.horizontalAnchor, width: lineWidthsPixels[index]) - textureMinX,
                y: baselinePixels - textureMinY
            )
            CTLineDraw(line, context)
        }

        guard let image = context.makeImage() else { return nil }

        let pixelToWorld = CGFloat(text.height) / fontSizePixels
        let verticalOffset = textVerticalOffset(
            anchor: text.verticalAnchor,
            ascent: Float(ascentPixels * pixelToWorld),
            descent: Float(descentPixels * pixelToWorld),
            lineAdvance: Float(lineAdvancePixels * pixelToWorld),
            lineCount: lines.count
        )
        let minX = Float(textureMinX * pixelToWorld) * text.widthFactor
        let maxX = Float(textureMaxX * pixelToWorld) * text.widthFactor
        let minY = Float(textureMinY * pixelToWorld) + verticalOffset
        let maxY = Float(textureMaxY * pixelToWorld) + verticalOffset
        let radians = text.rotation * .pi / 180.0
        let cosValue = cos(radians)
        let sinValue = sin(radians)

        let bottomLeft = transformTextPoint(SIMD2(minX, minY), insertion: text.insertion, cosValue: cosValue, sinValue: sinValue)
        let bottomRight = transformTextPoint(SIMD2(maxX, minY), insertion: text.insertion, cosValue: cosValue, sinValue: sinValue)
        let topRight = transformTextPoint(SIMD2(maxX, maxY), insertion: text.insertion, cosValue: cosValue, sinValue: sinValue)
        let topLeft = transformTextPoint(SIMD2(minX, maxY), insertion: text.insertion, cosValue: cosValue, sinValue: sinValue)

        let vertices = [
            RenderTextVertex(position: bottomLeft, texCoord: SIMD2(0, 1), color: color),
            RenderTextVertex(position: bottomRight, texCoord: SIMD2(1, 1), color: color),
            RenderTextVertex(position: topRight, texCoord: SIMD2(1, 0), color: color),
            RenderTextVertex(position: bottomLeft, texCoord: SIMD2(0, 1), color: color),
            RenderTextVertex(position: topRight, texCoord: SIMD2(1, 0), color: color),
            RenderTextVertex(position: topLeft, texCoord: SIMD2(0, 0), color: color),
        ]

        return RenderTextSprite(image: image, vertices: vertices)
    }

    private static func renderLines(for text: DXFText) -> [DXFTextLine] {
        text.lines
            .map {
                DXFTextLine(
                    content: $0.content.trimmingCharacters(in: .whitespacesAndNewlines),
                    isBold: $0.isBold
                )
            }
            .filter { !$0.content.isEmpty }
    }

    private static let registerBundledTextFonts: Void = {
        guard let url = Bundle.main.url(forResource: "NationalPark-wght", withExtension: "ttf")
            ?? Bundle.main.url(forResource: "NationalPark-wght", withExtension: "ttf", subdirectory: "Fonts/NationalPark") else {
            return
        }
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }()

    private static func textFont(named fontName: String, size: CGFloat, isBold: Bool = false) -> CTFont {
        _ = registerBundledTextFonts
        let normalizedFontName = DXFRenderStyle.normalizedTextFontName(fontName)
        let font = CTFontCreateWithName(normalizedFontName as CFString, size, nil)
        guard isBold else { return font }
        if let boldFont = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) {
            return boldFont
        }

        let descriptor = CTFontCopyFontDescriptor(font)
        let traits: [CFString: Any] = [
            kCTFontSymbolicTrait: CTFontSymbolicTraits.traitBold.rawValue,
            kCTFontWeightTrait: 0.4,
        ]
        let attributes: [CFString: Any] = [kCTFontTraitsAttribute: traits]
        let boldDescriptor = CTFontDescriptorCreateCopyWithAttributes(descriptor, attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(boldDescriptor, size, nil)
    }

    private static func textVerticalOffset(anchor: DXFTextVerticalAnchor, font: CTFont, lineCount: Int, fontScale: Float) -> Float {
        textVerticalOffset(
            anchor: anchor,
            ascent: Float(CTFontGetAscent(font)) * fontScale,
            descent: Float(CTFontGetDescent(font)) * fontScale,
            lineAdvance: Float(CTFontGetSize(font) * 1.35) * fontScale,
            lineCount: lineCount
        )
    }

    private static func textVerticalOffset(
        anchor: DXFTextVerticalAnchor,
        ascent: Float,
        descent: Float,
        lineAdvance: Float,
        lineCount: Int
    ) -> Float {
        let top = ascent
        let bottom = -descent - lineAdvance * Float(max(lineCount - 1, 0))

        switch anchor {
        case .baseline:
            return 0
        case .top:
            return -top
        case .middle:
            return -(top + bottom) * 0.5
        case .bottom:
            return -bottom
        }
    }

    private static func textHorizontalOffset(anchor: DXFTextHorizontalAnchor, width: Float) -> Float {
        switch anchor {
        case .left:
            return 0
        case .center:
            return -width * 0.5
        case .right:
            return -width
        }
    }

    private static func textHorizontalOffset(anchor: DXFTextHorizontalAnchor, width: CGFloat) -> CGFloat {
        switch anchor {
        case .left:
            return 0
        case .center:
            return -width * 0.5
        case .right:
            return -width
        }
    }

    private static func flattenedSegments(from path: CGPath) -> [(SIMD2<Float>, SIMD2<Float>)] {
        var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
        var current = SIMD2<Float>(0, 0)
        var subpathStart = SIMD2<Float>(0, 0)

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                current = simdPoint(element.points[0])
                subpathStart = current

            case .addLineToPoint:
                let end = simdPoint(element.points[0])
                segments.append((current, end))
                current = end

            case .addQuadCurveToPoint:
                let control = simdPoint(element.points[0])
                let end = simdPoint(element.points[1])
                var previous = current
                for step in 1...8 {
                    let t = Float(step) / 8.0
                    let next = quadraticBezier(start: current, control: control, end: end, t: t)
                    segments.append((previous, next))
                    previous = next
                }
                current = end

            case .addCurveToPoint:
                let control1 = simdPoint(element.points[0])
                let control2 = simdPoint(element.points[1])
                let end = simdPoint(element.points[2])
                var previous = current
                for step in 1...12 {
                    let t = Float(step) / 12.0
                    let next = cubicBezier(start: current, control1: control1, control2: control2, end: end, t: t)
                    segments.append((previous, next))
                    previous = next
                }
                current = end

            case .closeSubpath:
                segments.append((current, subpathStart))
                current = subpathStart

            @unknown default:
                break
            }
        }

        return segments
    }

    private static func transformTextPoint(
        _ point: SIMD2<Float>,
        insertion: SIMD2<Float>,
        cosValue: Float,
        sinValue: Float
    ) -> SIMD2<Float> {
        SIMD2(
            point.x * cosValue - point.y * sinValue,
            point.x * sinValue + point.y * cosValue
        ) + insertion
    }

    private static func simdPoint(_ point: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(point.x), Float(point.y))
    }

    private static func quadraticBezier(
        start: SIMD2<Float>,
        control: SIMD2<Float>,
        end: SIMD2<Float>,
        t: Float
    ) -> SIMD2<Float> {
        let inverse = 1.0 - t
        return start * inverse * inverse + control * 2.0 * inverse * t + end * t * t
    }

    private static func cubicBezier(
        start: SIMD2<Float>,
        control1: SIMD2<Float>,
        control2: SIMD2<Float>,
        end: SIMD2<Float>,
        t: Float
    ) -> SIMD2<Float> {
        let inverse = 1.0 - t
        let startTerm = start * (inverse * inverse * inverse)
        let control1Term = control1 * (3.0 * inverse * inverse * t)
        let control2Term = control2 * (3.0 * inverse * t * t)
        let endTerm = end * (t * t * t)
        return startTerm + control1Term + control2Term + endTerm
    }

    private static func normalizedSweep(from startAngle: Float, to endAngle: Float) -> Float {
        var sweep = endAngle - startAngle
        while sweep <= 0 {
            sweep += 360
        }
        return sweep
    }
}
