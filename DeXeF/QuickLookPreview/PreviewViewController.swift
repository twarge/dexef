// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Cocoa
import MetalKit
import Quartz

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var metalView: MTKView?
    private var renderer: MetalRenderer?
    private let viewport = ViewportController()
    private var scene: DXFScene?
    private var visibleLayers: Set<String> = []
    private var renderStyle = DXFRenderStyle(palette: .standardDark)

    override func loadView() {
        let view = QuickLookMetalView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), device: MTLCreateSystemDefaultDevice())
        view.autoresizingMask = [.width, .height]
        view.appearanceDidChange = { [weak self] in
            self?.updateRenderStyleForCurrentAppearance(redraw: true)
        }

        metalView = view
        self.view = view

        renderer = MetalRenderer(view: view)
        view.delegate = renderer
        updateRenderStyleForCurrentAppearance(redraw: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateRenderStyleForCurrentAppearance(redraw: true)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let scene = try DXFPreviewDrawing.scene(from: url)
        let visibleLayers = visibleLayerNames(for: scene)

        await MainActor.run {
            self.scene = scene
            self.visibleLayers = visibleLayers
            viewport.reset()
            updateRenderStyleForCurrentAppearance(redraw: false)
            renderer?.update(scene: scene, visibleLayers: visibleLayers, viewport: viewport, renderStyle: renderStyle)
            metalView?.draw()
        }
    }

    private func updateRenderStyleForCurrentAppearance(redraw: Bool) {
        guard let metalView else { return }

        let mode = RenderColorMode(metalView.effectiveAppearance)
        let palette: DXFRenderPalette = mode == .dark ? .standardDark : .standardLight
        let nextStyle = DXFRenderStyle(palette: palette)
        renderStyle = nextStyle
        metalView.clearColor = nextStyle.palette.background.quickLookMetalClearColor

        guard redraw, let scene else {
            return
        }

        renderer?.update(scene: scene, visibleLayers: visibleLayers, viewport: viewport, renderStyle: nextStyle)
        metalView.draw()
    }

    private func visibleLayerNames(for scene: DXFScene) -> Set<String> {
        let defaultVisible = scene.layers.filter(\.isVisibleByDefault).map(\.name)
        if defaultVisible.isEmpty {
            return Set(scene.layers.map(\.name))
        }
        return Set(defaultVisible)
    }
}

private final class QuickLookMetalView: MTKView {
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

private extension RenderColor {
    var quickLookMetalClearColor: MTLClearColor {
        MTLClearColor(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }
}
