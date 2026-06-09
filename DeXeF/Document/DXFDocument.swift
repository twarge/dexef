// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    // DXF is an ASCII text interchange format. Declaring it as `.image`
    // makes DocumentManager treat new documents as images, which breaks the
    // FileDocument serialize/import path used by NewDocumentButton on iOS
    // ("com.apple.DocumentManager error 1" / "Content serialization failed").
    static let dxf = UTType(exportedAs: "com.twarge.dexef.dxf", conformingTo: .text)
    static let libreOfficeDXF = UTType(importedAs: "org.libreoffice.dxf-document", conformingTo: .text)
    static let firmshellDXF = UTType(importedAs: "com.firmshell.dxfdrawing", conformingTo: .text)
}

struct DXFDocument: FileDocument, Identifiable {
    static var readableContentTypes: [UTType] {
        uniqueContentTypes([
            UTType(filenameExtension: "dxf"),
            UTType(filenameExtension: "DXF"),
            UTType(mimeType: "image/vnd.dxf"),
            .dxf,
            .libreOfficeDXF,
            .firmshellDXF,
        ])
    }

    static var writableContentTypes: [UTType] {
        [.dxf]
    }

    let id = UUID()
    let displayName: String
    let sourceText: String
    let scene: DXFScene

    init() {
        displayName = "Untitled.dxf"
        sourceText = ""
        scene = .empty
    }

    init(displayName: String, sourceText: String) {
        self.displayName = displayName
        self.sourceText = sourceText
        scene = DXFParser.parse(sourceText)
    }

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let text = DXFDocument.decode(data: data)

        self.init(displayName: url.lastPathComponent, sourceText: text)
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        let text = DXFDocument.decode(data: data)

        self.init(displayName: configuration.file.preferredFilename ?? "Drawing.dxf", sourceText: text)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: Data(sourceText.utf8))
        wrapper.preferredFilename = displayName
        return wrapper
    }

    private static func decode(data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func uniqueContentTypes(_ types: [UTType?]) -> [UTType] {
        var seen: Set<String> = []
        var uniqueTypes: [UTType] = []

        for type in types.compactMap(\.self) where seen.insert(type.identifier).inserted {
            uniqueTypes.append(type)
        }

        return uniqueTypes
    }
}
