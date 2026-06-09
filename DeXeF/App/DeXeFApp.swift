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
    #if os(iOS)
    @UIApplicationDelegateAdaptor(DemoDocumentBrowserInstaller.self) private var demoDocumentBrowserInstaller
    #endif

    var body: some Scene {
        documentScene

        #if os(iOS)
        if #available(iOS 18.0, *) {
            DocumentGroupLaunchScene("DeXeF") {
                DefaultDocumentGroupLaunchActions()
                NewDocumentButton("Open Demo Document", for: DXFDocument.self, contentType: .dxf) {
                    try DemoDocument.document()
                }
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
        DocumentGroup(newDocument: DXFDocument()) { file in
            ViewerView(document: file.document)
                .preferredColorScheme(AppTheme.stored(themeRawValue).colorScheme)
        }
        .commands {
            ViewerCommands()
        }
        #else
        DocumentGroup(viewing: DXFDocument.self) { file in
            ViewerView(document: file.document)
                .preferredColorScheme(AppTheme.stored(themeRawValue).colorScheme)
        }
        .commands {
            ViewerCommands()
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
@MainActor
private final class DemoDocumentBrowserInstaller: NSObject, UIApplicationDelegate {
    private static let demoButtonTag = 0xD3EFFE

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard #unavailable(iOS 18.0) else { return true }
        scheduleInstall()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard #unavailable(iOS 18.0) else { return }
        scheduleInstall()
    }

    private func scheduleInstall() {
        for delay in [0.0, 0.2, 0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.installDemoButtons()
            }
        }
    }

    private static func installDemoButtons() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            for browser in documentBrowsers(in: window.rootViewController) {
                installDemoButton(in: browser)
            }
        }
    }

    private static func installDemoButton(in browser: UIDocumentBrowserViewController) {
        guard !browser.additionalTrailingNavigationBarButtonItems.contains(where: { $0.tag == demoButtonTag }) else {
            return
        }

        let action = UIAction(
            title: "Open Demo Document",
            image: UIImage(systemName: "doc.text.magnifyingglass")
        ) { [weak browser] _ in
            guard let browser else { return }
            openDemoDocument(from: browser)
        }

        let button = UIBarButtonItem(primaryAction: action)
        button.tag = demoButtonTag
        button.title = "Demo"
        button.accessibilityLabel = "Open Demo Document"

        browser.additionalTrailingNavigationBarButtonItems =
            browser.additionalTrailingNavigationBarButtonItems + [button]
    }

    private static func openDemoDocument(from browser: UIDocumentBrowserViewController) {
        do {
            let sourceURL = try DemoDocument.localDocumentURL()
            browser.revealDocument(at: sourceURL, importIfNeeded: false) { revealedURL, _ in
                openDocument(at: revealedURL ?? sourceURL, from: browser)
            }
        } catch {
            return
        }
    }

    private static func openDocument(at url: URL, from browser: UIDocumentBrowserViewController) {
        let selector = #selector(UIDocumentBrowserViewControllerDelegate.documentBrowser(_:didPickDocumentsAt:))
        if let delegate = browser.delegate, delegate.responds(to: selector) {
            delegate.documentBrowser?(browser, didPickDocumentsAt: [url])
        } else {
            UIApplication.shared.open(url)
        }
    }

    private static func documentBrowsers(in rootViewController: UIViewController?) -> [UIDocumentBrowserViewController] {
        guard let rootViewController else { return [] }

        var browsers: [UIDocumentBrowserViewController] = []
        if let browser = rootViewController as? UIDocumentBrowserViewController {
            browsers.append(browser)
        }

        for child in rootViewController.children {
            browsers.append(contentsOf: documentBrowsers(in: child))
        }

        if let navigationController = rootViewController as? UINavigationController {
            for viewController in navigationController.viewControllers {
                browsers.append(contentsOf: documentBrowsers(in: viewController))
            }
        }

        if let tabBarController = rootViewController as? UITabBarController {
            for viewController in tabBarController.viewControllers ?? [] {
                browsers.append(contentsOf: documentBrowsers(in: viewController))
            }
        }

        if let presentedViewController = rootViewController.presentedViewController {
            browsers.append(contentsOf: documentBrowsers(in: presentedViewController))
        }

        return browsers
    }
}
#endif

private enum DemoDocument {
    static var bundledURL: URL? {
        Bundle.main.url(forResource: "DemoEntities", withExtension: "dxf")
    }

    static func document() throws -> DXFDocument {
        guard let bundledURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        return try DXFDocument(url: bundledURL)
    }

    static func localDocumentURL() throws -> URL {
        guard let bundledURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destinationURL = documentsURL.appendingPathComponent("DeXeF Demo.dxf")

        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.copyItem(at: bundledURL, to: destinationURL)
        }
        return destinationURL
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
            showsHUD?.wrappedValue ?? true
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
