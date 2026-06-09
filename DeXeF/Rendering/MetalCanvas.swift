// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import MetalKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let twoFingerPanSpeedMultiplier: CGFloat = 2

struct MetalCanvas: View {
    let scene: DXFScene
    let visibleLayers: Set<String>
    let renderStyle: DXFRenderStyle
    var selectionState = MetalSelectionState()
    @ObservedObject var viewport: ViewportController
    var minimumContentInsets = ViewportInsets.zero
    var onPointerMoved: ((CGPoint, CGSize, ViewportInsets) -> Void)?
    var onPointerEnded: (() -> Void)?
    var onSelectAt: ((CGPoint, CGSize, ViewportInsets) -> Void)?

    @State private var dragStartPan: SIMD2<Float>?

    var body: some View {
        GeometryReader { proxy in
            let contentInsets = ViewportInsets(proxy.safeAreaInsets).merged(withMinimum: minimumContentInsets)
            let style = renderStyle.withContentInsets(contentInsets)

            MetalCanvasView(scene: scene, visibleLayers: visibleLayers, viewport: viewport, renderStyle: style, selectionState: selectionState)
                .background(renderStyle.palette.background.swiftUIColor)
                .gesture(dragGesture(in: proxy.size))
                .simultaneousGesture(selectionGesture(in: proxy.size, contentInsets: contentInsets))
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case let .active(location):
                        onPointerMoved?(location, proxy.size, contentInsets)
                    case .ended:
                        onPointerEnded?()
                    }
                }
                .crosshairCursor()
        }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartPan == nil {
                    dragStartPan = viewport.pan
                }

                viewport.pan(by: value.translation, from: dragStartPan ?? viewport.pan, in: size)
            }
            .onEnded { _ in
                dragStartPan = nil
            }
    }

    private func selectionGesture(in size: CGSize, contentInsets: ViewportInsets) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                onPointerMoved?(value.location, size, contentInsets)
                onSelectAt?(value.location, size, contentInsets)
            }
    }
}

#if os(macOS)
struct MetalCanvasView: NSViewRepresentable {
    let scene: DXFScene
    let visibleLayers: Set<String>
    let viewport: ViewportController
    let renderStyle: DXFRenderStyle
    let selectionState: MetalSelectionState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        makeView(context: context)
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(scene: scene, visibleLayers: visibleLayers, viewport: viewport, renderStyle: renderStyle, selectionState: selectionState)
    }

    private func makeView(context: Context) -> MTKView {
        let view = DXFMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        context.coordinator.attach(to: view, viewport: viewport)
        context.coordinator.update(scene: scene, visibleLayers: visibleLayers, viewport: viewport, renderStyle: renderStyle, selectionState: selectionState)
        return view
    }
}

private final class DXFMetalView: MTKView {
    weak var viewportController: ViewportController?
    var contentInsets = ViewportInsets.zero
    private var isDrawingForLiveResize = false

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        configureResizeRendering()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        configureResizeRendering()
    }

    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSizeForCurrentBounds()
        drawDuringLiveResize()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        updateDrawableSizeForCurrentBounds()
        drawDuringLiveResize()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updateDrawableSizeForCurrentBounds()
        draw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSizeForCurrentBounds()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateDrawableSizeForCurrentBounds()
            self.draw()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let viewportController else {
            super.scrollWheel(with: event)
            return
        }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? twoFingerPanSpeedMultiplier : 8
        let translation = CGSize(
            width: event.scrollingDeltaX * multiplier,
            height: event.scrollingDeltaY * multiplier
        )
        viewportController.pan(by: translation, in: bounds.size)
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let topLeftLocation = CGPoint(
            x: location.x,
            y: isFlipped ? location.y : bounds.height - location.y
        )
        viewportController?.magnify(
            by: max(0.05, 1.0 + Float(event.magnification)),
            around: topLeftLocation,
            in: bounds.size,
            contentInsets: contentInsets
        )
    }

    private func configureResizeRendering() {
        autoResizeDrawable = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    private func updateDrawableSizeForCurrentBounds() {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let backingSize = convertToBacking(bounds.size)
        guard backingSize.width.isFinite, backingSize.height.isFinite, backingSize.width > 0, backingSize.height > 0 else {
            return
        }

        let nextSize = CGSize(
            width: max(backingSize.width, 1),
            height: max(backingSize.height, 1)
        )

        if drawableSize != nextSize {
            drawableSize = nextSize
        }
    }

    private func drawDuringLiveResize() {
        guard inLiveResize || window?.inLiveResize == true, !isDrawingForLiveResize else { return }

        isDrawingForLiveResize = true
        draw()
        isDrawingForLiveResize = false
    }
}
#else
struct MetalCanvasView: UIViewRepresentable {
    let scene: DXFScene
    let visibleLayers: Set<String>
    let viewport: ViewportController
    let renderStyle: DXFRenderStyle
    let selectionState: MetalSelectionState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        makeView(context: context)
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(scene: scene, visibleLayers: visibleLayers, viewport: viewport, renderStyle: renderStyle, selectionState: selectionState)
    }

    private func makeView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        context.coordinator.attach(to: view, viewport: viewport)
        context.coordinator.update(scene: scene, visibleLayers: visibleLayers, viewport: viewport, renderStyle: renderStyle, selectionState: selectionState)
        return view
    }
}
#endif

private extension View {
    @ViewBuilder
    func crosshairCursor() -> some View {
        #if os(macOS)
        modifier(CrosshairCursorModifier())
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct CrosshairCursorModifier: ViewModifier {
    @State private var isCursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                if isHovering, !isCursorPushed {
                    NSCursor.crosshair.push()
                    isCursorPushed = true
                } else if !isHovering, isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
            .onDisappear {
                if isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
    }
}
#endif

final class Coordinator: NSObject {
    private var renderer: MetalRenderer?
    private weak var metalView: MTKView?
    private weak var viewport: ViewportController?
    private var renderStyle = DXFRenderStyle()

    func attach(to view: MTKView, viewport: ViewportController) {
        metalView = view
        self.viewport = viewport

        renderer = MetalRenderer(view: view)
        view.delegate = renderer

        #if os(macOS)
        (view as? DXFMetalView)?.viewportController = viewport
        #else
        installTouchGestures(on: view)
        #endif
    }

    func update(
        scene: DXFScene,
        visibleLayers: Set<String>,
        viewport: ViewportController,
        renderStyle: DXFRenderStyle,
        selectionState: MetalSelectionState = MetalSelectionState()
    ) {
        self.viewport = viewport
        self.renderStyle = renderStyle

        #if os(macOS)
        if let view = metalView as? DXFMetalView {
            view.viewportController = viewport
            view.contentInsets = renderStyle.contentInsets
        }
        #endif

        renderer?.update(scene: scene, visibleLayers: visibleLayers, viewport: viewport, renderStyle: renderStyle, selectionState: selectionState)
    }

    #if os(iOS)
    private weak var gestureView: MTKView?
    private var touchPanStart: SIMD2<Float>?
    private var isPinching = false
    private var pinchStartZoom: Float?
    private var pinchStartPan: SIMD2<Float>?
    private var pinchStartAnchor: CGPoint?
    private var postPinchPanStart: SIMD2<Float>?
    private var postPinchMoveStart: CGPoint?

    private func installTouchGestures(on view: MTKView) {
        gestureView = view
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        // Also receive indirect two-finger scrolls from a trackpad or Magic
        // Mouse. Scroll input bypasses the touch-count gate above, so the same
        // recognizer drives both direct two-finger panning and trackpad panning
        // (with momentum).
        pan.allowedScrollTypesMask = .all
        pan.delegate = self
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view, let viewport else { return }
        guard !isPinching else {
            touchPanStart = nil
            recognizer.setTranslation(.zero, in: view)
            return
        }

        switch recognizer.state {
        case .began:
            touchPanStart = viewport.pan
        case .changed:
            let translation = recognizer.translation(in: view)
            viewport.pan(
                by: CGSize(
                    width: translation.x * twoFingerPanSpeedMultiplier,
                    height: translation.y * twoFingerPanSpeedMultiplier
                ),
                from: touchPanStart ?? viewport.pan,
                in: view.bounds.size
            )
        default:
            touchPanStart = nil
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let viewport, let view = recognizer.view else { return }

        switch recognizer.state {
        case .began:
            beginPinch(from: recognizer, in: view, viewport: viewport)
            touchPanStart = nil
        case .changed:
            // A trackpad (indirect) pinch reports zero touches — treat it as a
            // pinch. Only a single remaining direct touch means the user lifted
            // a finger mid-pinch and is now panning.
            if recognizer.numberOfTouches == 1 {
                continuePostPinchMove(with: recognizer, in: view, viewport: viewport)
                return
            }

            if postPinchMoveStart != nil {
                beginPinch(from: recognizer, in: view, viewport: viewport)
                return
            }

            if pinchStartZoom == nil || pinchStartPan == nil || pinchStartAnchor == nil {
                beginPinch(from: recognizer, in: view, viewport: viewport)
                return
            }

            viewport.pinch(
                from: pinchStartZoom ?? viewport.zoom,
                startPan: pinchStartPan ?? viewport.pan,
                startAnchor: pinchStartAnchor ?? recognizer.location(in: view),
                to: recognizer.location(in: view),
                scale: Float(recognizer.scale),
                in: view.bounds.size,
                contentInsets: renderStyle.contentInsets
            )
        default:
            clearPinchTracking()
            touchPanStart = nil
        }
    }

    private func beginPinch(from recognizer: UIPinchGestureRecognizer, in view: UIView, viewport: ViewportController) {
        isPinching = true
        pinchStartZoom = viewport.zoom
        pinchStartPan = viewport.pan
        pinchStartAnchor = recognizer.location(in: view)
        postPinchPanStart = nil
        postPinchMoveStart = nil
        recognizer.scale = 1
    }

    private func continuePostPinchMove(with recognizer: UIPinchGestureRecognizer, in view: UIView, viewport: ViewportController) {
        isPinching = false
        pinchStartZoom = nil
        pinchStartPan = nil
        pinchStartAnchor = nil

        let location = recognizer.location(in: view)
        guard let moveStart = postPinchMoveStart,
              let panStart = postPinchPanStart else {
            postPinchMoveStart = location
            postPinchPanStart = viewport.pan
            return
        }

        viewport.pan(
            by: CGSize(
                width: location.x - moveStart.x,
                height: location.y - moveStart.y
            ),
            from: panStart,
            in: view.bounds.size
        )
    }

    private func clearPinchTracking() {
        isPinching = false
        pinchStartZoom = nil
        pinchStartPan = nil
        pinchStartAnchor = nil
        postPinchPanStart = nil
        postPinchMoveStart = nil
    }
    #endif
}

#if os(iOS)
extension Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
