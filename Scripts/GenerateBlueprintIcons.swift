// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

// Draws the DXF document icon at every size the asset catalog, the Info.plist
// and the macOS iconset need:
//
//     swift Scripts/GenerateBlueprintIcons.swift
//
// The app icon is not drawn here: Scripts/GenerateAppIcon.swift writes it.

import AppKit
import CoreGraphics
import Foundation

enum BlueprintIconGenerator {
    static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let imageSetDirectory = root.appendingPathComponent("DeXeF/Assets.xcassets/DXFDocumentIcon.imageset")
    static let resourceDirectory = root.appendingPathComponent("DeXeF/Resources")
    static let documentIconSetDirectory = resourceDirectory.appendingPathComponent("DXFDocument.iconset")

    static func run() throws {
        try FileManager.default.createDirectory(at: imageSetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentIconSetDirectory, withIntermediateDirectories: true)

        for size in documentImageSizes {
            try drawIcon(
                pixels: size.pixels,
                destination: imageSetDirectory.appendingPathComponent(size.filename)
            )
        }

        for size in documentResourceSizes {
            try drawIcon(
                pixels: size.pixels,
                destination: resourceDirectory.appendingPathComponent(size.filename)
            )
        }

        for size in macDocumentIconSizes {
            try drawIcon(
                pixels: size.pixels,
                destination: documentIconSetDirectory.appendingPathComponent(size.filename)
            )
        }
    }

    private static func drawIcon(pixels: Int, destination: URL) throws {
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
        drawDocumentIcon(in: CGRect(origin: .zero, size: size), context: context)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw IconError.couldNotEncode
        }

        try data.write(to: destination)
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

        // The cone keeps the app icon's coordinates, a 1024-unit square with y
        // downward, and goes in the middle of the page.
        let unit = rect.width / 1024 * coneScale
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: unit, y: -unit)
        context.translateBy(x: -512, y: -512)
        drawCone(context: context, unit: unit)
        context.restoreGState()

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

    // The cone is the app icon's, which Scripts/GenerateAppIcon.swift draws
    // from the same numbers, in dark ink for the pale page: change the two
    // together. The numbers are in that icon's coordinates.
    private static let axisX: CGFloat = 512
    private static let apexY: CGFloat = 224
    private static let baseY: CGFloat = 704
    private static let baseRadiusX: CGFloat = 288
    private static let baseRadiusY: CGFloat = 96
    private static let standOff: CGFloat = 64

    /// The cone's size on the page, as a share of its size in the app icon.
    private static let coneScale: CGFloat = 0.85

    /// Draws the cone, with its centre lines and dimension lines, in the app
    /// icon's coordinates. `unit` is the size of one of those units in pixels,
    /// which keeps the lines from thinning away in the smallest images.
    private static func drawCone(context: CGContext, unit: CGFloat) {
        let ink = color(0x12395B)
        let rim = color(0x2A89A4)
        let construction = color(0x3B6F8E, alpha: 0.36)
        let edgeWidth = max(34, 1.25 / unit)
        let farRimWidth = max(22, 1.0 / unit)
        let thin = max(11, 0.75 / unit)

        // The cone is seen from a little above, so its sides do not run to
        // the ends of the base: they touch the ellipse slightly higher up and
        // further in.
        let height = baseY - apexY
        let tangentY = baseY - baseRadiusY * baseRadiusY / height
        let tangentReach = baseRadiusX * (1 - (baseRadiusY / height) * (baseRadiusY / height)).squareRoot()
        let apex = CGPoint(x: axisX, y: apexY)
        let leftTangent = CGPoint(x: axisX - tangentReach, y: tangentY)
        let rightTangent = CGPoint(x: axisX + tangentReach, y: tangentY)

        // Angles are round the cone's axis, from straight ahead. The surface
        // in view, and the near rim under it, run a little past a quarter
        // turn either way.
        let reach = CGFloat.pi / 2 + asin(baseRadiusY / height)
        func rimPoint(_ angle: CGFloat) -> CGPoint {
            CGPoint(x: axisX + baseRadiusX * sin(angle), y: baseY + baseRadiusY * cos(angle))
        }
        func addRim(to path: CGMutablePath, from start: CGFloat, to end: CGFloat, continuing: Bool = false) {
            let steps = 96
            for index in 0...steps {
                let point = rimPoint(start + (end - start) * CGFloat(index) / CGFloat(steps))
                if index == 0 && !continuing {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }

        context.saveGState()
        context.setLineJoin(.round)

        // The centre lines, dashed outward from the middle of the base so
        // that they cross on a dash, and the width and height. They are one
        // path, so that nothing doubles up where they meet.
        let centre = CGPoint(x: axisX, y: baseY)
        let left = axisX - baseRadiusX
        let right = axisX + baseRadiusX
        let dimensionX = right + standOff
        let dimensionY = baseY + baseRadiusY + standOff
        let lines = CGMutablePath()
        addDashes(to: lines, from: centre, to: CGPoint(x: axisX, y: apexY - standOff))
        addDashes(to: lines, from: centre, to: CGPoint(x: axisX, y: dimensionY))
        addDashes(to: lines, from: centre, to: CGPoint(x: left - standOff, y: baseY))
        addDashes(to: lines, from: centre, to: CGPoint(x: dimensionX, y: baseY))
        addDimensionLine(to: lines, from: CGPoint(x: left, y: dimensionY), to: CGPoint(x: right, y: dimensionY), tick: 44)
        addDimensionLine(to: lines, from: CGPoint(x: dimensionX, y: baseY), to: CGPoint(x: dimensionX, y: apexY), tick: 38)
        context.setLineCap(.round)
        context.setStrokeColor(construction)
        context.setLineWidth(thin)
        context.addPath(lines)
        context.strokePath()

        // The far rim of the base, which shows through the cone.
        let farRim = CGMutablePath()
        addRim(to: farRim, from: reach, to: 2 * .pi - reach)
        context.setStrokeColor(rim)
        context.setLineWidth(farRimWidth)
        context.addPath(farRim)
        context.strokePath()

        // The surface, see-through, shaded round the cone from a light at the
        // front left: a fan of slivers from the apex, each one flat colour and
        // running under the next. In the small images the slivers are thinner
        // than a pixel and no longer cover the surface between them, so the
        // whole surface is first filled with a plain left-to-right gradient of
        // the same colours.
        let lightAngle = -40 * CGFloat.pi / 180
        func shade(_ angle: CGFloat) -> CGColor {
            let facing = (cos(angle - lightAngle) + 1) / 2
            let level = facing * facing
            return level < 0.5
                ? mix(surfaceDeep, surfaceMid, level * 2)
                : mix(surfaceMid, surfaceLight, level * 2 - 1)
        }

        let surface = CGMutablePath()
        surface.move(to: leftTangent)
        surface.addLine(to: apex)
        surface.addLine(to: rightTangent)
        addRim(to: surface, from: reach, to: -reach, continuing: true)
        surface.closeSubpath()

        context.saveGState()
        context.setAlpha(surfaceOpacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        let stopCount = 12
        let stops = (0...stopCount).map { CGFloat($0) / CGFloat(stopCount) }
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: stops.map { shade(asin($0 * 2 - 1)) } as CFArray,
            locations: stops
        ) {
            context.saveGState()
            context.addPath(surface)
            context.clip()
            context.drawLinearGradient(gradient, start: CGPoint(x: left, y: 0), end: CGPoint(x: right, y: 0), options: [])
            context.restoreGState()
        }

        let sliverCount = 160
        let step = 2 * reach / CGFloat(sliverCount)
        for index in 0..<sliverCount {
            let from = -reach + CGFloat(index) * step
            let to = index == sliverCount - 1 ? reach : from + step * 1.4
            context.beginPath()
            context.move(to: apex)
            context.addLine(to: rimPoint(from))
            context.addLine(to: rimPoint(to))
            context.closePath()
            context.setFillColor(shade(from + step / 2))
            context.fillPath()
        }

        context.endTransparencyLayer()
        context.restoreGState()

        // The outline: the two sides and the near rim. They meet end to end
        // where the sides touch the base, so the sides run a touch past that
        // point and the rim is drawn over them.
        let overlap: CGFloat = 3
        let sideLength = hypot(tangentReach, tangentY - apexY)
        let dx = tangentReach / sideLength * overlap
        let dy = (tangentY - apexY) / sideLength * overlap
        context.setLineCap(.butt)
        context.setLineWidth(edgeWidth)
        context.setStrokeColor(ink)
        context.beginPath()
        context.move(to: CGPoint(x: leftTangent.x - dx, y: tangentY + dy))
        context.addLine(to: apex)
        context.addLine(to: CGPoint(x: rightTangent.x + dx, y: tangentY + dy))
        context.strokePath()

        let nearRim = CGMutablePath()
        addRim(to: nearRim, from: -reach, to: reach)
        context.setStrokeColor(rim)
        context.addPath(nearRim)
        context.strokePath()

        context.restoreGState()
    }

    // The cone's surface where it faces the light, where it turns away, and
    // on its far side.
    private static let surfaceLight = color(0xFFFFFF)
    private static let surfaceMid = color(0x7FC6E6)
    private static let surfaceDeep = color(0x2B78AE)
    private static let surfaceOpacity: CGFloat = 0.6

    private static func mix(_ a: CGColor, _ b: CGColor, _ part: CGFloat) -> CGColor {
        guard let from = a.components, let to = b.components, from.count == 4, to.count == 4 else { return a }
        return CGColor(
            red: from[0] + (to[0] - from[0]) * part,
            green: from[1] + (to[1] - from[1]) * part,
            blue: from[2] + (to[2] - from[2]) * part,
            alpha: from[3] + (to[3] - from[3]) * part
        )
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

    /// Adds a dashed line as separate segments, spaced so that both ends
    /// finish on a full dash.
    private static func addDashes(to path: CGMutablePath, from start: CGPoint, to end: CGPoint, dash: CGFloat = 22, gap: CGFloat = 21) {
        let length = hypot(end.x - start.x, end.y - start.y)
        let count = max(1, Int(((length + gap) / (dash + gap)).rounded()))
        let pitch = (length - dash) / CGFloat(max(1, count - 1))
        let ux = (end.x - start.x) / length
        let uy = (end.y - start.y) / length
        for index in 0..<count {
            let from = CGFloat(index) * pitch
            path.move(to: CGPoint(x: start.x + ux * from, y: start.y + uy * from))
            path.addLine(to: CGPoint(x: start.x + ux * (from + dash), y: start.y + uy * (from + dash)))
        }
    }

    /// Adds a dimension line with a tick across each end.
    private static func addDimensionLine(to path: CGMutablePath, from start: CGPoint, to end: CGPoint, tick: CGFloat) {
        let horizontal = abs(start.y - end.y) < 0.001
        let dx: CGFloat = horizontal ? 0 : tick
        let dy: CGFloat = horizontal ? tick : 0
        path.move(to: start)
        path.addLine(to: end)
        for point in [start, end] {
            path.move(to: CGPoint(x: point.x - dx, y: point.y - dy))
            path.addLine(to: CGPoint(x: point.x + dx, y: point.y + dy))
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

    private enum IconError: Error {
        case missingContext
        case couldNotEncode
    }

    private struct IconSize {
        let filename: String
        let pixels: Int
    }

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
