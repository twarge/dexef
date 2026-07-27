// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if os(macOS)
import AppKit

/// Auto-hides the window toolbar while distraction-free mode is on, revealing
/// it when the pointer approaches the top of the window. The hide/show state
/// is published back to SwiftUI, which toggles the toolbar *by value*
/// (`.toolbar(_:for: .windowToolbar)`) so the canvas view is never rebuilt.
struct DistractionFreeWindowChromeConfigurator: NSViewRepresentable {
    var isEnabled: Bool
    var onChromeHiddenChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        ChromeView(isEnabled: isEnabled, onChromeHiddenChange: onChromeHiddenChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let chromeView = nsView as? ChromeView else { return }
        chromeView.onChromeHiddenChange = onChromeHiddenChange
        chromeView.isEnabled = isEnabled
    }

    final class ChromeView: NSView {
        var isEnabled: Bool {
            didSet {
                guard oldValue != isEnabled else { return }
                applyMode()
            }
        }

        var onChromeHiddenChange: (Bool) -> Void

        private weak var configuredWindow: NSWindow?
        private weak var trackingView: NSView?
        private var trackingArea: NSTrackingArea?
        private var isChromeHidden = false
        private let revealHeight: CGFloat = 92
        // Once shown, the toolbar stays until the pointer drops this much
        // further, so it doesn't strobe at the lower edge of the reveal strip.
        private let revealHysteresis: CGFloat = 48
        // The hide is debounced: the pointer must stay out of the reveal strip
        // this long before the chrome hides, so transient excursions while
        // crossing toolbar items don't strobe it.
        private var hideTask: Task<Void, Never>?

        init(isEnabled: Bool, onChromeHiddenChange: @escaping (Bool) -> Void) {
            self.isEnabled = isEnabled
            self.onChromeHiddenChange = onChromeHiddenChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        isolated deinit {
            removeTrackingArea()
            restoreWindowChrome()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyMode()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyMode()
        }

        private func applyMode() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.syncConfiguredWindow()

                guard self.isEnabled else {
                    self.removeTrackingArea()
                    self.restoreWindowChrome()
                    self.onChromeHiddenChange(false)
                    return
                }

                self.installTrackingAreaIfNeeded()
                self.updateChromeVisibilityForCurrentPointer()
            }
        }

        private func syncConfiguredWindow() {
            guard configuredWindow !== window else { return }
            removeTrackingArea()
            restoreWindowChrome()
            configuredWindow = window
            isChromeHidden = false
        }

        private func installTrackingAreaIfNeeded() {
            guard let contentView = configuredWindow?.contentView else { return }
            guard trackingArea == nil || trackingView !== contentView else { return }
            removeTrackingArea()

            let options: NSTrackingArea.Options = [
                .activeInKeyWindow,
                .enabledDuringMouseDrag,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
            ]
            let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            contentView.addTrackingArea(area)
            trackingArea = area
            trackingView = contentView
        }

        private func removeTrackingArea() {
            if let trackingArea, let trackingView {
                trackingView.removeTrackingArea(trackingArea)
            }
            trackingArea = nil
            trackingView = nil
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            updateChromeVisibilityFor(event)
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            updateChromeVisibilityFor(event)
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            updateChromeVisibilityFor(event)
        }

        override func rightMouseDragged(with event: NSEvent) {
            super.rightMouseDragged(with: event)
            updateChromeVisibilityFor(event)
        }

        override func otherMouseDragged(with event: NSEvent) {
            super.otherMouseDragged(with: event)
            updateChromeVisibilityFor(event)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            updateChromeVisibilityFor(event)
        }

        private func updateChromeVisibilityFor(_ event: NSEvent) {
            guard isEnabled, let window = configuredWindow else { return }
            if isPointerInRevealArea(of: window, event: event) {
                cancelPendingHide()
                setWindowChromeHidden(false)
            } else {
                scheduleHide()
            }
        }

        private func updateChromeVisibilityForCurrentPointer() {
            guard isEnabled, let window = configuredWindow else { return }
            if isPointerInRevealArea(of: window) {
                cancelPendingHide()
                setWindowChromeHidden(false)
            } else {
                scheduleHide()
            }
        }

        private func scheduleHide() {
            guard !isChromeHidden, hideTask == nil else { return }
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, !Task.isCancelled else { return }
                self.hideTask = nil
                guard self.isEnabled, let window = self.configuredWindow,
                      !self.isPointerInRevealArea(of: window) else { return }
                self.setWindowChromeHidden(true)
            }
        }

        private func cancelPendingHide() {
            hideTask?.cancel()
            hideTask = nil
        }

        private func isPointerInRevealArea(of window: NSWindow) -> Bool {
            isScreenPointInRevealArea(NSEvent.mouseLocation, of: window)
        }

        private func isPointerInRevealArea(of window: NSWindow, event: NSEvent) -> Bool {
            let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? NSEvent.mouseLocation
            return isScreenPointInRevealArea(point, of: window)
        }

        private func isScreenPointInRevealArea(_ point: NSPoint, of window: NSWindow) -> Bool {
            let frame = window.frame
            guard point.x >= frame.minX, point.x <= frame.maxX else { return false }
            // Test the top strip inclusively (the toolbar itself sits on the
            // window's max-Y edge), and hold the toolbar a little further down
            // once shown (hysteresis).
            let distanceFromTop = frame.maxY - point.y
            guard distanceFromTop >= 0 else { return false }
            let limit = isChromeHidden ? revealHeight : revealHeight + revealHysteresis
            return distanceFromTop <= limit
        }

        private func setWindowChromeHidden(_ hidden: Bool) {
            guard isChromeHidden != hidden else { return }
            isChromeHidden = hidden
            // The traffic lights are deliberately left untouched: hiding them
            // (even via alpha) makes ⌘W/⌘M silently no-op, because
            // performClose:/performMiniaturize: simulate a click on them.
            onChromeHiddenChange(hidden)
        }

        private func restoreWindowChrome() {
            cancelPendingHide()
            isChromeHidden = false
        }
    }
}
#endif
