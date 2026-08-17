// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import CoreTransferable
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum DocumentExportFormat: String, CaseIterable, Identifiable {
    case dxf
    case pdf
    case png

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .dxf: return "DXF"
        case .pdf: return "PDF"
        case .png: return "PNG"
        }
    }

    var contentType: UTType {
        switch self {
        case .dxf: return .dxf
        case .pdf: return .pdf
        case .png: return .png
        }
    }

    var filenameExtension: String { rawValue }
}

enum DocumentTransfer {
    static func data(for document: DXFDocument, format: DocumentExportFormat) -> Data? {
        switch format {
        case .dxf:
            return Data(document.sourceText.utf8)
        case .pdf:
            let size = DXFPreviewDrawing.preferredSize(for: document.scene, maxDimension: 1600)
            return DXFPreviewDrawing.pdfData(for: document.scene, size: size)
        case .png:
            return pngData(for: document.scene)
        }
    }

    static func exportFilename(for document: DXFDocument, format: DocumentExportFormat) -> String {
        let base = (document.displayName as NSString).deletingPathExtension
        return base.isEmpty ? "Drawing" : base
    }

    static func copyToPasteboard(_ document: DXFDocument, format: DocumentExportFormat) {
        switch format {
        case .dxf:
            setPasteboardText(document.sourceText)
        case .pdf, .png:
            guard let data = data(for: document, format: format) else { return }
            setPasteboardData(data, type: format.contentType)
        }
    }

    /// DXF text from the clipboard, if it plausibly is DXF: either a string
    /// payload containing a DXF section marker or data tagged with a DXF type.
    static func clipboardDXFText() -> String? {
        if let text = pasteboardText(), looksLikeDXF(text) {
            return text
        }
        return nil
    }

    /// Stages clipboard DXF as a file so the document machinery can open it
    /// like any other document, and returns the URL. On macOS a temporary file
    /// suffices (the viewer opens it in place); on iOS it goes into Documents
    /// so the new file is visible in the browser either way.
    static func stageClipboardDocument() throws -> URL {
        guard let text = clipboardDXFText() else {
            throw CocoaError(.fileReadCorruptFile)
        }

        #if os(macOS)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardDocuments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #else
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        #endif

        let url = directory.appendingPathComponent("Clipboard \(Self.stagingStamp()).dxf")
        try Data(text.utf8).write(to: url)
        return url
    }

    private static func stagingStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        return formatter.string(from: Date())
    }

    private static func looksLikeDXF(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.contains("SECTION") || text.contains("ENTITIES") || text.contains("HEADER")
    }

    private static func pngData(for scene: DXFScene) -> Data? {
        let size = DXFPreviewDrawing.preferredSize(for: scene, maxDimension: 1600)
        let scale: CGFloat = 2
        let width = max(Int(size.width * scale), 1)
        let height = max(Int(size.height * scale), 1)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        DXFPreviewDrawing.draw(scene: scene, in: CGRect(origin: .zero, size: size), context: context, style: .preview)

        guard let image = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func setPasteboardText(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private static func setPasteboardData(_ data: Data, type: UTType) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        #else
        UIPasteboard.general.setData(data, forPasteboardType: type.identifier)
        #endif
    }

    private static func pasteboardText() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return UIPasteboard.general.string
        #endif
    }
}

/// One rendered export of a document, typed for transfer: the payload behind
/// the share affordances on both platforms. Constructing it is a value copy;
/// the DXF, PDF, or PNG bytes are only produced when a share target asks.
struct DocumentShareFile: Transferable {
    var document: DXFDocument
    var format: DocumentExportFormat

    var filename: String {
        DocumentTransfer.exportFilename(for: document, format: format) + "." + format.filenameExtension
    }

    func data() throws -> Data {
        guard let data = DocumentTransfer.data(for: document, format: format) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    /// One representation per export format, each offered only for the
    /// instance that carries it — so a receiver is never offered DXF text
    /// under a PNG type. Spelled through the typed helper below to keep the
    /// builder within the type-checker's budget.
    static var transferRepresentation: some TransferRepresentation {
        fileRepresentation(.dxf)
        fileRepresentation(.pdf)
        fileRepresentation(.png)
    }

    private static func fileRepresentation(
        _ type: UTType
    ) -> some TransferRepresentation<DocumentShareFile> {
        let representation = FileRepresentation<DocumentShareFile>(exportedContentType: type) {
            (file: DocumentShareFile) async throws -> SentTransferredFile in
            SentTransferredFile(try file.writeTemporaryFile(), allowAccessingOriginalFile: false)
        }
        return representation.exportingCondition { (file: DocumentShareFile) -> Bool in
            file.format.contentType == type
        }
    }

    /// File transfers hand over a URL, so the bytes go through a uniquely-named
    /// temporary directory — which is also what lets the receiver see the real
    /// filename.
    func writeTemporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try data().write(to: url)
        return url
    }
}

/// Write-only payload for `fileExporter`.
struct DataExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [] }
    static var writableContentTypes: [UTType] { [.dxf, .pdf, .png] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct DocumentTransferCommands: Commands {
    @FocusedValue(\.viewerDocument) private var document
    @FocusedValue(\.exportDocumentAction) private var exportDocument
    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    #endif

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Document from Clipboard") {
                openClipboardDocument()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .saveItem) {
            #if os(macOS)
            Button("Save DXF…") {
                resolvedExportAction?(.dxf)
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(commandsAreDisabled)
            #endif

            Menu("Export As") {
                ForEach(DocumentExportFormat.allCases) { format in
                    Button("\(format.menuTitle)…") {
                        resolvedExportAction?(format)
                    }
                }
            }
            .disabled(commandsAreDisabled)

            // macOS-only: the iPadOS menu bar shares these Commands, but iOS
            // shares through the viewer toolbar's ShareLink menu instead, and
            // NSSharingServicePicker has no UIKit counterpart here.
            #if os(macOS)
            Menu("Share") {
                ForEach(DocumentExportFormat.allCases) { format in
                    Button(format.menuTitle) {
                        if let document = resolvedDocument {
                            DocumentSharePresenter.share(document, format: format)
                        }
                    }
                }
            }
            .disabled(commandsAreDisabled)
            #endif
        }

        CommandGroup(after: .pasteboard) {
            Menu("Copy As") {
                ForEach(DocumentExportFormat.allCases) { format in
                    Button(format.menuTitle) {
                        if let document = resolvedDocument {
                            DocumentTransfer.copyToPasteboard(document, format: format)
                        }
                    }
                }
            }
            .disabled(commandsAreDisabled)
        }
    }

    // On iOS, focused scene values only reach commands while some view holds
    // focus, which the Metal canvas never does — so the document is resolved
    // through ActiveViewerDocument at invocation time instead, and the items
    // stay enabled (they no-op without a document). macOS keys focused values
    // off the key window, so they work as-is and drive the disabled state.
    private var resolvedDocument: DXFDocument? {
        #if os(macOS)
        return document
        #else
        return document ?? ActiveViewerDocument.shared.document
        #endif
    }

    private var resolvedExportAction: ((DocumentExportFormat) -> Void)? {
        #if os(macOS)
        return exportDocument
        #else
        return exportDocument ?? ActiveViewerDocument.shared.exportAction
        #endif
    }

    private var commandsAreDisabled: Bool {
        #if os(macOS)
        return document == nil
        #else
        return false
        #endif
    }

    private func openClipboardDocument() {
        guard let url = try? DocumentTransfer.stageClipboardDocument() else {
            #if os(macOS)
            NSSound.beep()
            #endif
            return
        }

        #if os(macOS)
        Task {
            try? await openDocument(at: url)
        }
        #else
        // SwiftUI offers no programmatic document-open on iOS, so hand the
        // staged file to the document browser the same way the pre-iOS-18 demo
        // button does. Even if the open is refused, the file is already in
        // Documents and shows up in the browser.
        ClipboardDocumentOpener.open(url)
        #endif
    }
}

#if os(macOS)
/// Presents the system share picker for one rendered export, anchored on the
/// key window's content view. The picker is retained for the duration of the
/// presentation and released once a service is chosen or the menu dismissed.
@MainActor
private enum DocumentSharePresenter {
    private static var activePicker: NSSharingServicePicker?
    private static let pickerDelegate = PickerDelegate()

    static func share(_ document: DXFDocument, format: DocumentExportFormat) {
        guard let url = try? DocumentShareFile(document: document, format: format).writeTemporaryFile(),
              let anchor = NSApp.keyWindow?.contentView
        else {
            NSSound.beep()
            return
        }

        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = pickerDelegate
        activePicker = picker
        picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
    }

    private final class PickerDelegate: NSObject, NSSharingServicePickerDelegate {
        // Called with the chosen service, or nil on dismissal; either way the
        // presentation is over and the picker can go. Delivered on the main
        // thread, so it is safe to assume isolation.
        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            MainActor.assumeIsolated {
                DocumentSharePresenter.activePicker = nil
            }
        }
    }
}
#endif

#if os(iOS)
/// The most recently active viewer's document and export hook, read by menu
/// commands at invocation time. Updated whenever a viewer appears, changes
/// document, or its scene becomes active, so on iPad the last-focused window
/// wins.
@MainActor
final class ActiveViewerDocument {
    static let shared = ActiveViewerDocument()

    var document: DXFDocument?
    var exportAction: ((DocumentExportFormat) -> Void)?
}

@MainActor
private enum ClipboardDocumentOpener {
    static func open(_ url: URL) {
        guard let browser = firstDocumentBrowser() else {
            UIApplication.shared.open(url)
            return
        }

        browser.revealDocument(at: url, importIfNeeded: false) { revealedURL, _ in
            let target = revealedURL ?? url
            let selector = #selector(UIDocumentBrowserViewControllerDelegate.documentBrowser(_:didPickDocumentsAt:))
            if let delegate = browser.delegate, delegate.responds(to: selector) {
                delegate.documentBrowser?(browser, didPickDocumentsAt: [target])
            } else {
                UIApplication.shared.open(target)
            }
        }
    }

    private static func firstDocumentBrowser() -> UIDocumentBrowserViewController? {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                if let browser = documentBrowser(in: window.rootViewController) {
                    return browser
                }
            }
        }
        return nil
    }

    private static func documentBrowser(in viewController: UIViewController?) -> UIDocumentBrowserViewController? {
        guard let viewController else { return nil }

        if let browser = viewController as? UIDocumentBrowserViewController {
            return browser
        }

        for child in viewController.children {
            if let browser = documentBrowser(in: child) {
                return browser
            }
        }

        if let presented = viewController.presentedViewController {
            return documentBrowser(in: presented)
        }

        return nil
    }
}
#endif

struct ViewerDocumentKey: FocusedValueKey {
    typealias Value = DXFDocument
}

struct ExportDocumentActionKey: FocusedValueKey {
    typealias Value = (DocumentExportFormat) -> Void
}

extension FocusedValues {
    var viewerDocument: DXFDocument? {
        get { self[ViewerDocumentKey.self] }
        set { self[ViewerDocumentKey.self] = newValue }
    }

    var exportDocumentAction: ((DocumentExportFormat) -> Void)? {
        get { self[ExportDocumentActionKey.self] }
        set { self[ExportDocumentActionKey.self] = newValue }
    }
}
