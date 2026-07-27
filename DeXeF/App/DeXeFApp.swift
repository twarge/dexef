// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

@main
struct DeXeFApp: App {
    @AppStorage(PreferenceKeys.theme) private var themeRawValue = AppTheme.system.rawValue

    var body: some Scene {
        documentScene

        #if os(iOS)
        if #available(iOS 18.0, *) {
            DocumentGroupLaunchScene("DeXeF") {
                DemoDocumentLaunchButton()
            }
        }
        #endif

        #if os(macOS)
        Settings {
            PreferencesView()
                .preferredColorScheme(AppTheme.stored(themeRawValue).colorScheme)
        }
        #endif
    }

    private var documentScene: some Scene {
        #if os(iOS)
        DocumentGroup(newDocument: DemoDocument.defaultDocument()) { file in
            ViewerView(document: file.document)
                .preferredColorScheme(AppTheme.stored(themeRawValue).colorScheme)
        }
        .commands {
            ViewerCommands()
            NewWindowCommands()
            DocumentTransferCommands()
        }
        #else
        DocumentGroup(viewing: DXFDocument.self) { file in
            ViewerView(document: file.document)
                .preferredColorScheme(AppTheme.stored(themeRawValue).colorScheme)
        }
        .commands {
            ViewerCommands()
            DocumentTransferCommands()
            #if os(macOS)
            DemoDocumentCommands()
            AppInfoCommands()
            SidebarCommands()
            #endif
        }
        #endif
    }
}

#if os(macOS)
private struct DemoDocumentCommands: Commands {
    @Environment(\.openDocument) private var openDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Demo Document") {
                openDemoDocument()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }

    private func openDemoDocument() {
        guard let url = DemoDocument.bundledURL else {
            NSSound.beep()
            return
        }

        Task {
            try? await openDocument(at: url)
        }
    }
}

private struct AppInfoCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About DeXeF") {
                AboutPanel.show()
            }
        }
    }
}

@MainActor
private enum AboutPanel {
    static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "DeXeF",
            .version: versionText,
            .credits: credits
        ])
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private static var credits: NSAttributedString {
        let text = """
        DeXeF
        Made by Twarge LLC.
        Contact: hello@twarge.com

        Licenses

        DeXeF
        Application source code is licensed under the Apache License, Version 2.0.
        Copyright © 2026 Twarge LLC.
        DeXeF is provided on an "AS IS" basis, without warranties or conditions of any kind. See the bundled LICENSE file for the full license text.

        App Artwork
        Generated icons and bundled document artwork are copyright © 2026 Twarge LLC.

        Apple Platform Frameworks
        DeXeF uses Apple system frameworks including SwiftUI, AppKit, UIKit, Metal, MetalKit, Quick Look, and Uniform Type Identifiers. These frameworks are provided by Apple under the applicable Apple SDK and platform license terms.

        DXF File Format
        AutoCAD DXF is a file format associated with Autodesk. DeXeF includes an independent DXF parser and does not bundle Autodesk code.

        National Park Font
        National Park is bundled from Google Fonts and licensed under the SIL Open Font License, Version 1.1. Copyright 2025 The National Park Project Authors.
        """

        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )

        let email = "hello@twarge.com"
        let range = (text as NSString).range(of: email)
        if range.location != NSNotFound,
           let mailURL = URL(string: "mailto:\(email)") {
            attributedString.addAttributes([
                .link: mailURL,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: range)
        }

        return attributedString
    }
}
#endif

#if os(iOS)
// ⌘N opens a fresh window (scene) showing the document browser. This replaces
// the system's New Document shortcut; creating documents stays available from
// the browser's "+". Requires UIApplicationSupportsMultipleScenes (declared in
// Info-iOS.plist), and only iPad shows multiple windows — on iPhone the
// request is a no-op.
private struct NewWindowCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest())
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
    }
}

@available(iOS 18.0, *)
private struct DemoDocumentLaunchButton: View {
    var body: some View {
        // The template overload creates an empty file on hardware. The plain
        // button asks DocumentGroup to serialize its demo-filled default value.
        NewDocumentButton("Open Demo Document")
    }
}
#endif

/// Anchors resource lookup to the bundle that contains this code, whatever the
/// hosting process's main bundle happens to be.
private final class DeXeFBundleToken {}

private enum DemoDocument {
    static var bundledURL: URL? {
        // The bundle holding this code first: `Bundle.main` is wrong in any
        // process that isn't the app itself.
        for bundle in [Bundle(for: DeXeFBundleToken.self), Bundle.main] {
            if let url = bundle.url(forResource: "DemoEntities", withExtension: "dxf") {
                return url
            }
        }
        return nil
    }

    static func document() throws -> DXFDocument {
        guard let bundledURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: bundledURL, options: [.mappedIfSafe])
        guard !data.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try DXFDocument(url: bundledURL)
    }

    /// Supplies the value serialized by the plain iOS NewDocumentButton.
    /// macOS uses a viewing-only DocumentGroup and never calls this factory.
    static func defaultDocument() -> DXFDocument {
        #if os(iOS)
        do {
            let document = try document()
            NSLog("DeXeF: prepared %d-byte demo document", document.sourceText.utf8.count)
            return document
        } catch {
            NSLog("DeXeF: could not prepare demo document — %@", error.localizedDescription)
            return DXFDocument()
        }
        #else
        return DXFDocument()
        #endif
    }
}

private struct ViewerCommands: Commands {
    @FocusedValue(\.defaultZoomAction) private var defaultZoomAction
    @FocusedValue(\.clearSelectionAction) private var clearSelectionAction
    @FocusedValue(\.showsHUD) private var showsHUD

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Show HUD", isOn: showsHUDBinding)
                .disabled(showsHUD == nil)

            Button("Default Zoom") {
                defaultZoomAction?()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(defaultZoomAction == nil)

            Button("Clear Selection") {
                clearSelectionAction?()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(clearSelectionAction == nil)
        }
    }

    private var showsHUDBinding: Binding<Bool> {
        Binding {
            showsHUD?.wrappedValue ?? false
        } set: { newValue in
            showsHUD?.wrappedValue = newValue
        }
    }
}

private struct DefaultZoomActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ClearSelectionActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ShowsHUDKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var defaultZoomAction: (() -> Void)? {
        get { self[DefaultZoomActionKey.self] }
        set { self[DefaultZoomActionKey.self] = newValue }
    }

    var clearSelectionAction: (() -> Void)? {
        get { self[ClearSelectionActionKey.self] }
        set { self[ClearSelectionActionKey.self] = newValue }
    }

    var showsHUD: Binding<Bool>? {
        get { self[ShowsHUDKey.self] }
        set { self[ShowsHUDKey.self] = newValue }
    }
}
