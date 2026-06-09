// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics
import Foundation

enum BlueprintIconGenerator {
    static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let appIconDirectory = root.appendingPathComponent("DeXeF/Assets.xcassets/AppIcon.appiconset")
    static let imageSetDirectory = root.appendingPathComponent("DeXeF/Assets.xcassets/DXFDocumentIcon.imageset")
    static let resourceDirectory = root.appendingPathComponent("DeXeF/Resources")
    static let documentIconSetDirectory = resourceDirectory.appendingPathComponent("DXFDocument.iconset")

    static func run() throws {
        try FileManager.default.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imageSetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentIconSetDirectory, withIntermediateDirectories: true)

        for size in appIconSizes {
            try drawIcon(
                pixels: size.pixels,
                destination: appIconDirectory.appendingPathComponent(size.filename),
                style: .app
            )
        }

        for size in documentImageSizes {
            try drawIcon(
                pixels: size.pixels,
                destination: imageSetDirectory.appendingPathComponent(size.filename),
                style: .document
            )
        }

        for size in documentResourceSizes {
            try drawIcon(
                pixels: size.pixels,
                destination: resourceDirectory.appendingPathComponent(size.filename),
                style: .document
            )
        }

        for size in macDocumentIconSizes {
            try drawIcon(
                pixels: size.pixels,
                destination: documentIconSetDirectory.appendingPathComponent(size.filename),
                style: .document
            )
        }
    }

    private static func drawIcon(pixels: Int, destination: URL, style: IconStyle) throws {
        let size = CGSize(width: pixels, height: pixels)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
            throw IconError.missingContext
        }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.clear(CGRect(origin: .zero, size: size))

        switch style {
        case .app:
            drawAppIcon(in: CGRect(origin: .zero, size: size), context: context)
        case .document:
            drawDocumentIcon(in: CGRect(origin: .zero, size: size), context: context)
        }

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw IconError.couldNotEncode
        }

        try data.write(to: destination)
    }

    private static func drawAppIcon(in rect: CGRect, context: CGContext) {
        context.saveGState()
        let radius = rect.width * 0.22
        let outer = CGPath(roundedRect: rect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.03), cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(outer)
        context.clip()

        drawBlueprintBackground(in: rect, context: context, colorA: color(0x071625), colorB: color(0x12385A))
        drawGrid(in: rect, context: context, spacing: rect.width / 8.0, alpha: 0.28)
        drawGrid(in: rect, context: context, spacing: rect.width / 32.0, alpha: 0.09)

        let plate = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.15)
        drawBlueprintSheet(in: plate, context: context, cornerRadius: rect.width * 0.055, fillAlpha: 0.16)
        drawCone(in: plate.insetBy(dx: plate.width * 0.14, dy: plate.height * 0.16), context: context, lineScale: rect.width)
        drawWarmReferenceMark(in: plate, context: context)

        context.restoreGState()

        context.addPath(outer)
        context.setStrokeColor(color(0xB7E6FF, alpha: 0.26))
        context.setLineWidth(max(1, rect.width * 0.014))
        context.strokePath()
    }

    private static func drawDocumentIcon(in rect: CGRect, context: CGContext) {
        context.saveGState()
        let pageRect = rect.insetBy(dx: rect.width * 0.13, dy: rect.height * 0.08)
        let radius = rect.width * 0.055
        let pagePath = CGPath(roundedRect: pageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.setShadow(offset: CGSize(width: 0, height: -rect.height * 0.03), blur: rect.width * 0.055, color: color(0x081522, alpha: 0.22))
        context.addPath(pagePath)
        context.setFillColor(color(0xF4FAFF))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        context.saveGState()
        context.addPath(pagePath)
        context.clip()
        drawBlueprintBackground(in: pageRect, context: context, colorA: color(0xF2F8FC), colorB: color(0xD7EAF8))
        drawGrid(in: pageRect, context: context, spacing: rect.width / 10.0, alpha: 0.22, dark: true)
        drawGrid(in: pageRect, context: context, spacing: rect.width / 40.0, alpha: 0.10, dark: true)
        drawCone(in: pageRect.insetBy(dx: pageRect.width * 0.13, dy: pageRect.height * 0.18), context: context, lineScale: rect.width, darkInk: true)
        context.restoreGState()

        drawFold(in: pageRect, context: context)

        context.addPath(pagePath)
        context.setStrokeColor(color(0x2C5878, alpha: 0.34))
        context.setLineWidth(max(1, rect.width * 0.01))
        context.strokePath()

        context.restoreGState()
    }

    private static func drawBlueprintBackground(in rect: CGRect, context: CGContext, colorA: CGColor, colorB: CGColor) {
        let colors = [colorA, colorB] as CFArray
        let locations: [CGFloat] = [0, 1]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    private static func drawBlueprintSheet(in rect: CGRect, context: CGContext, cornerRadius: CGFloat, fillAlpha: CGFloat) {
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.setFillColor(color(0xDDF4FF, alpha: fillAlpha))
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor(color(0xDDF4FF, alpha: 0.35))
        context.setLineWidth(max(1, rect.width * 0.013))
        context.strokePath()
    }

    private static func drawGrid(in rect: CGRect, context: CGContext, spacing: CGFloat, alpha: CGFloat, dark: Bool = false) {
        guard spacing > 1 else { return }

        context.saveGState()
        context.setStrokeColor(dark ? color(0x3D6B8A, alpha: alpha) : color(0xB7E6FF, alpha: alpha))
        context.setLineWidth(max(0.5, rect.width * 0.0013))

        var x = rect.minX
        while x <= rect.maxX {
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY
        while y <= rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        context.strokePath()
        context.restoreGState()
    }

    private static func drawCone(in rect: CGRect, context: CGContext, lineScale: CGFloat, darkInk: Bool = false) {
        let ink = darkInk ? color(0x12395B) : color(0xF4FBFF)
        let secondary = darkInk ? color(0x2A89A4, alpha: 0.68) : color(0x6FE7FF, alpha: 0.78)
        let construction = darkInk ? color(0x3B6F8E, alpha: 0.36) : color(0xB7E6FF, alpha: 0.32)
        let width = max(1.25, lineScale * 0.026)
        let thin = max(0.75, lineScale * 0.009)

        let apex = CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.09)
        let leftBase = CGPoint(x: rect.minX + rect.width * 0.11, y: rect.minY + rect.height * 0.22)
        let rightBase = CGPoint(x: rect.maxX - rect.width * 0.11, y: leftBase.y)
        let baseRect = CGRect(
            x: leftBase.x,
            y: leftBase.y - rect.height * 0.115,
            width: rightBase.x - leftBase.x,
            height: rect.height * 0.23
        )

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.setStrokeColor(construction)
        context.setLineWidth(thin)
        drawDashedLine(from: CGPoint(x: apex.x, y: rect.minY + rect.height * 0.06), to: CGPoint(x: apex.x, y: rect.maxY), context: context, dash: lineScale * 0.018)
        drawDashedLine(from: CGPoint(x: rect.minX, y: baseRect.midY), to: CGPoint(x: rect.maxX, y: baseRect.midY), context: context, dash: lineScale * 0.018)

        context.setStrokeColor(secondary)
        context.setLineWidth(max(1.0, lineScale * 0.012))
        drawEllipseArc(in: baseRect, start: 0, end: .pi, context: context)
        context.strokePath()

        context.setStrokeColor(construction)
        drawEllipseArc(in: baseRect, start: .pi, end: .pi * 2, context: context)
        context.replacePathWithStrokedPath()
        context.setAlpha(darkInk ? 0.55 : 0.42)
        context.fillPath()
        context.setAlpha(1)

        context.setStrokeColor(ink)
        context.setLineWidth(width)
        context.beginPath()
        context.move(to: leftBase)
        context.addLine(to: apex)
        context.addLine(to: rightBase)
        context.strokePath()

        context.setStrokeColor(secondary)
        context.setLineWidth(width * 0.72)
        drawEllipseArc(in: baseRect, start: 0, end: .pi, context: context)
        context.strokePath()

        context.setStrokeColor(construction)
        context.setLineWidth(thin)
        drawDimensionLine(from: CGPoint(x: leftBase.x, y: rect.minY + rect.height * 0.05), to: CGPoint(x: rightBase.x, y: rect.minY + rect.height * 0.05), tick: lineScale * 0.035, context: context)
        drawDimensionLine(from: CGPoint(x: rect.maxX - rect.width * 0.02, y: baseRect.midY), to: CGPoint(x: rect.maxX - rect.width * 0.02, y: apex.y), tick: lineScale * 0.03, context: context)

        context.restoreGState()
    }

    private static func drawWarmReferenceMark(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color(0xF6C35B, alpha: 0.9))
        context.setLineWidth(max(1, rect.width * 0.018))
        let radius = rect.width * 0.05
        let center = CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.12)
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.restoreGState()
    }

    private static func drawFold(in rect: CGRect, context: CGContext) {
        let fold = rect.width * 0.25
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(color(0xC2DFF2, alpha: 0.86))
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor(color(0x2C5878, alpha: 0.25))
        context.setLineWidth(max(1, rect.width * 0.008))
        context.strokePath()
    }

    private static func drawDashedLine(from start: CGPoint, to end: CGPoint, context: CGContext, dash: CGFloat) {
        context.saveGState()
        context.setLineDash(phase: 0, lengths: [dash, dash * 0.9])
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawDimensionLine(from start: CGPoint, to end: CGPoint, tick: CGFloat, context: CGContext) {
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        if abs(start.y - end.y) < 0.001 {
            context.move(to: CGPoint(x: start.x, y: start.y - tick))
            context.addLine(to: CGPoint(x: start.x, y: start.y + tick))
            context.move(to: CGPoint(x: end.x, y: end.y - tick))
            context.addLine(to: CGPoint(x: end.x, y: end.y + tick))
        } else {
            context.move(to: CGPoint(x: start.x - tick, y: start.y))
            context.addLine(to: CGPoint(x: start.x + tick, y: start.y))
            context.move(to: CGPoint(x: end.x - tick, y: end.y))
            context.addLine(to: CGPoint(x: end.x + tick, y: end.y))
        }
        context.strokePath()
    }

    private static func drawEllipseArc(in rect: CGRect, start: CGFloat, end: CGFloat, context: CGContext) {
        let steps = 42
        context.beginPath()
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let angle = start + (end - start) * t
            let point = CGPoint(
                x: rect.midX + cos(angle) * rect.width * 0.5,
                y: rect.midY + sin(angle) * rect.height * 0.5
            )
            if index == 0 {
                context.move(to: point)
            } else {
                context.addLine(to: point)
            }
        }
    }

    private static func color(_ hex: Int, alpha: CGFloat = 1.0) -> CGColor {
        CGColor(
            red: CGFloat((hex >> 16) & 0xff) / 255.0,
            green: CGFloat((hex >> 8) & 0xff) / 255.0,
            blue: CGFloat(hex & 0xff) / 255.0,
            alpha: alpha
        )
    }

    private enum IconStyle {
        case app
        case document
    }

    private enum IconError: Error {
        case missingContext
        case couldNotEncode
    }

    private struct IconSize {
        let filename: String
        let pixels: Int
    }

    private static let appIconSizes: [IconSize] = [
        IconSize(filename: "app-16.png", pixels: 16),
        IconSize(filename: "app-20.png", pixels: 20),
        IconSize(filename: "app-29.png", pixels: 29),
        IconSize(filename: "app-32.png", pixels: 32),
        IconSize(filename: "app-40.png", pixels: 40),
        IconSize(filename: "app-58.png", pixels: 58),
        IconSize(filename: "app-60.png", pixels: 60),
        IconSize(filename: "app-64.png", pixels: 64),
        IconSize(filename: "app-76.png", pixels: 76),
        IconSize(filename: "app-80.png", pixels: 80),
        IconSize(filename: "app-87.png", pixels: 87),
        IconSize(filename: "app-120.png", pixels: 120),
        IconSize(filename: "app-128.png", pixels: 128),
        IconSize(filename: "app-152.png", pixels: 152),
        IconSize(filename: "app-167.png", pixels: 167),
        IconSize(filename: "app-180.png", pixels: 180),
        IconSize(filename: "app-256.png", pixels: 256),
        IconSize(filename: "app-512.png", pixels: 512),
        IconSize(filename: "app-1024.png", pixels: 1024),
    ]

    private static let documentImageSizes: [IconSize] = [
        IconSize(filename: "dxf-document-icon-1x.png", pixels: 128),
        IconSize(filename: "dxf-document-icon-2x.png", pixels: 256),
        IconSize(filename: "dxf-document-icon-3x.png", pixels: 384),
    ]

    private static let documentResourceSizes: [IconSize] = [
        IconSize(filename: "DXFDocumentIcon-64.png", pixels: 64),
        IconSize(filename: "DXFDocumentIcon-320.png", pixels: 320),
    ]

    private static let macDocumentIconSizes: [IconSize] = [
        IconSize(filename: "icon_16x16.png", pixels: 16),
        IconSize(filename: "icon_16x16@2x.png", pixels: 32),
        IconSize(filename: "icon_32x32.png", pixels: 32),
        IconSize(filename: "icon_32x32@2x.png", pixels: 64),
        IconSize(filename: "icon_128x128.png", pixels: 128),
        IconSize(filename: "icon_128x128@2x.png", pixels: 256),
        IconSize(filename: "icon_256x256.png", pixels: 256),
        IconSize(filename: "icon_256x256@2x.png", pixels: 512),
        IconSize(filename: "icon_512x512.png", pixels: 512),
        IconSize(filename: "icon_512x512@2x.png", pixels: 1024),
    ]
}

do {
    try BlueprintIconGenerator.run()
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
