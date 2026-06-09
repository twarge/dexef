// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Combine
import CoreGraphics
import simd

final class ViewportController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private(set) var zoom: Float = 1.0
    private(set) var pan = SIMD2<Float>(0, 0)

    func reset() {
        guard zoom != 1.0 || pan != SIMD2<Float>(0, 0) else { return }
        objectWillChange.send()
        zoom = 1.0
        pan = SIMD2(0, 0)
    }

    func restore(zoom: Float, pan: SIMD2<Float>) {
        let nextZoom = clampedZoom(zoom)
        guard nextZoom.isFinite, pan.x.isFinite, pan.y.isFinite else { return }
        guard nextZoom != self.zoom || pan != self.pan else { return }
        objectWillChange.send()
        self.zoom = nextZoom
        self.pan = pan
    }

    func setZoom(_ value: Float) {
        let nextZoom = clampedZoom(value)
        guard nextZoom != zoom else { return }

        objectWillChange.send()
        zoom = nextZoom
    }

    func magnify(by scale: Float) {
        guard scale.isFinite, scale > 0 else { return }
        setZoom(zoom * scale)
    }

    func magnify(by scale: Float, around anchor: CGPoint, in size: CGSize, contentInsets: ViewportInsets = .zero) {
        guard scale.isFinite, scale > 0, size.width > 0, size.height > 0 else { return }

        let previousZoom = zoom
        let nextZoom = clampedZoom(zoom * scale)
        let appliedScale = nextZoom / previousZoom
        let anchor = clipPoint(for: anchor, in: size)
        let fitOffset = fitOffset(in: size, contentInsets: contentInsets)

        let nextPan = pan * appliedScale + (anchor - fitOffset) * (1.0 - appliedScale)
        guard nextZoom != zoom || nextPan != pan else { return }

        objectWillChange.send()
        pan = nextPan
        zoom = nextZoom
    }

    func pinch(
        from startZoom: Float,
        startPan: SIMD2<Float>,
        startAnchor: CGPoint,
        to currentAnchor: CGPoint,
        scale: Float,
        in size: CGSize,
        contentInsets: ViewportInsets = .zero
    ) {
        guard startZoom.isFinite,
              startZoom > 0,
              startPan.x.isFinite,
              startPan.y.isFinite,
              scale.isFinite,
              scale > 0,
              size.width > 0,
              size.height > 0 else { return }

        let nextZoom = clampedZoom(startZoom * scale)
        let appliedScale = nextZoom / startZoom
        let startAnchor = clipPoint(for: startAnchor, in: size)
        let currentAnchor = clipPoint(for: currentAnchor, in: size)
        let fitOffset = fitOffset(in: size, contentInsets: contentInsets)
        let nextPan = startPan * appliedScale + (currentAnchor - fitOffset) - (startAnchor - fitOffset) * appliedScale

        guard nextZoom != zoom || nextPan != pan else { return }

        objectWillChange.send()
        pan = nextPan
        zoom = nextZoom
    }

    func pan(by translation: CGSize, from start: SIMD2<Float>, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let x = Float(translation.width / size.width) * 2.0
        let y = Float(translation.height / size.height) * -2.0
        let nextPan = SIMD2(start.x + x, start.y + y)
        guard nextPan != pan else { return }

        objectWillChange.send()
        pan = nextPan
    }

    func pan(by translation: CGSize, in size: CGSize) {
        pan(by: translation, from: pan, in: size)
    }

    private func clampedZoom(_ value: Float) -> Float {
        min(80.0, max(0.02, value))
    }

    private func clipPoint(for point: CGPoint, in size: CGSize) -> SIMD2<Float> {
        SIMD2(
            Float(point.x / size.width) * 2.0 - 1.0,
            1.0 - Float(point.y / size.height) * 2.0
        )
    }

    private func fitOffset(in size: CGSize, contentInsets: ViewportInsets) -> SIMD2<Float> {
        let width = Float(size.width)
        let height = Float(size.height)
        let leading = min(max(contentInsets.leading, 0), width - 1)
        let trailing = min(max(contentInsets.trailing, 0), width - leading - 1)
        let top = min(max(contentInsets.top, 0), height - 1)
        let bottom = min(max(contentInsets.bottom, 0), height - top - 1)
        let contentWidth = max(width - leading - trailing, 1)
        let contentHeight = max(height - top - bottom, 1)
        let contentCenterX = leading + contentWidth * 0.5
        let contentCenterY = top + contentHeight * 0.5

        return SIMD2(
            contentCenterX / width * 2.0 - 1.0,
            1.0 - contentCenterY / height * 2.0
        )
    }
}
