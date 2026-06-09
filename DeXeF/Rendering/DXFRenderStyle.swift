// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CoreGraphics
import simd
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ViewportInsets: Equatable {
    static let zero = ViewportInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    var top: Float
    var leading: Float
    var bottom: Float
    var trailing: Float

    init(top: Float, leading: Float, bottom: Float, trailing: Float) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    init(_ edgeInsets: EdgeInsets) {
        self.init(
            top: Float(edgeInsets.top),
            leading: Float(edgeInsets.leading),
            bottom: Float(edgeInsets.bottom),
            trailing: Float(edgeInsets.trailing)
        )
    }

    func scaled(from viewSize: CGSize, to drawableSize: CGSize) -> ViewportInsets {
        guard viewSize.width > 0, viewSize.height > 0 else { return self }

        let xScale = Float(drawableSize.width / viewSize.width)
        let yScale = Float(drawableSize.height / viewSize.height)
        return ViewportInsets(
            top: top * yScale,
            leading: leading * xScale,
            bottom: bottom * yScale,
            trailing: trailing * xScale
        )
    }

    func merged(withMinimum minimumInsets: ViewportInsets) -> ViewportInsets {
        ViewportInsets(
            top: max(top, minimumInsets.top),
            leading: max(leading, minimumInsets.leading),
            bottom: max(bottom, minimumInsets.bottom),
            trailing: max(trailing, minimumInsets.trailing)
        )
    }
}

enum PreferenceKeys {
    static let theme = "preferences.theme"
    static let lineThickness = "preferences.lineThickness"
    static let showsHUD = "preferences.showsHUD"
    static let showsGridMarks = "preferences.showsGridMarks"
    static let selectsCurveSegments = "preferences.selection.selectsCurveSegments"
    static let textFontName = "preferences.textFontName"
    static let coordinateDisplayUnit = "preferences.coordinateDisplayUnit"
    static let lightPalette = "preferences.palette.light"
    static let darkPalette = "preferences.palette.dark"
    static let lightPaletteColors = "preferences.palette.light.colors"
    static let darkPaletteColors = "preferences.palette.dark.colors"
}

enum DrawingTextFontPreset: String, CaseIterable, Identifiable {
    case nationalPark = "National Park"
    case helvetica = "Helvetica"
    case avenirNext = "Avenir Next"
    case menlo = "Menlo"
    case courier = "Courier"
    case times = "Times New Roman"

    var id: String { rawValue }

    var title: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    static func stored(_ rawValue: String) -> AppTheme {
        AppTheme(rawValue: rawValue) ?? .system
    }
}

enum RenderColorMode: Equatable {
    case light
    case dark

    init(_ colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    #if os(macOS)
    init(_ appearance: NSAppearance) {
        let match = appearance.bestMatch(from: [
            .aqua,
            .darkAqua,
            .vibrantLight,
            .vibrantDark,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantLight,
            .accessibilityHighContrastVibrantDark,
        ])

        switch match {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            self = .dark
        default:
            self = .light
        }
    }
    #endif
}

enum AdaptiveGrid {
    static let targetSpacingPixels: Float = 52
    static let markHalfLengthPixels: Float = 6

    static func spacing(forPixelsPerUnit pixelsPerUnit: Float) -> Float {
        guard pixelsPerUnit.isFinite, pixelsPerUnit > 0 else { return 1 }

        let rawSpacing = Double(targetSpacingPixels / pixelsPerUnit)
        guard rawSpacing.isFinite, rawSpacing > 0 else { return 1 }

        let base = pow(10.0, floor(log10(rawSpacing)))
        for multiplier in [1.0, 2.0, 5.0, 10.0] {
            let spacing = base * multiplier
            if spacing >= rawSpacing {
                return Float(spacing)
            }
        }

        return Float(base * 10.0)
    }
}

enum PalettePreset: String, CaseIterable, Identifiable {
    case studio
    case blueprint
    case garden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: return "Studio"
        case .blueprint: return "Blueprint"
        case .garden: return "Garden"
        }
    }

    static func stored(_ rawValue: String) -> PalettePreset {
        PalettePreset(rawValue: rawValue) ?? .studio
    }

    func palette(for mode: RenderColorMode) -> DXFRenderPalette {
        switch (self, mode) {
        case (.studio, .light):
            return DXFRenderPalette(
                name: "Studio Light",
                background: .hex(0xFFFFFF),
                grid: .hex(0x8EA0B7, alpha: 0.46),
                defaultStroke: .hex(0x0B1220),
                layerColors: [
                    .hex(0xB9344E),
                    .hex(0xA86612),
                    .hex(0x197A50),
                    .hex(0x087984),
                    .hex(0x234CBF),
                    .hex(0x7440B8),
                    .hex(0x070B12),
                    .hex(0x465668),
                    .hex(0x68798F),
                ]
            )

        case (.studio, .dark):
            return DXFRenderPalette(
                name: "Studio Dark",
                background: .hex(0x10144B),
                grid: .hex(0x3A36FF),
                defaultStroke: .hex(0xEDF2F7),
                layerColors: [
                    .hex(0xFF6B7A),
                    .hex(0xF6C35B),
                    .hex(0x4ADE80),
                    .hex(0x2DD4BF),
                    .hex(0x7AA2FF),
                    .hex(0xC084FC),
                    .hex(0xF8FAFC),
                    .hex(0x94A3B8),
                    .hex(0xCBD5E1),
                ]
            )

        case (.blueprint, .light):
            return DXFRenderPalette(
                name: "Blueprint Light",
                background: .hex(0xFFFFFF),
                grid: .hex(0x7F99B2, alpha: 0.5),
                defaultStroke: .hex(0x082845),
                layerColors: [
                    .hex(0xAD2E48),
                    .hex(0x93640B),
                    .hex(0x116B45),
                    .hex(0x057484),
                    .hex(0x1749A8),
                    .hex(0x5D34A6),
                    .hex(0x061F38),
                    .hex(0x43556C),
                    .hex(0x647C95),
                ]
            )

        case (.blueprint, .dark):
            return DXFRenderPalette(
                name: "Blueprint Dark",
                background: .hex(0x071A2F),
                grid: .hex(0x1F4262, alpha: 0.44),
                defaultStroke: .hex(0xDDF4FF),
                layerColors: [
                    .hex(0xFF687E),
                    .hex(0xF4C95D),
                    .hex(0x54D78D),
                    .hex(0x36D3E1),
                    .hex(0x7DB5FF),
                    .hex(0xB98CFF),
                    .hex(0xF0FBFF),
                    .hex(0x8EA9C3),
                    .hex(0xBCD5EA),
                ]
            )

        case (.garden, .light):
            return DXFRenderPalette(
                name: "Garden Light",
                background: .hex(0xFFFFFF),
                grid: .hex(0x909F8C, alpha: 0.48),
                defaultStroke: .hex(0x111D19),
                layerColors: [
                    .hex(0xAD3736),
                    .hex(0x987211),
                    .hex(0x197A4C),
                    .hex(0x087A7E),
                    .hex(0x2B55B7),
                    .hex(0x663EAA),
                    .hex(0x0B1410),
                    .hex(0x48584C),
                    .hex(0x6C7D70),
                ]
            )

        case (.garden, .dark):
            return DXFRenderPalette(
                name: "Garden Dark",
                background: .hex(0x071A2F),
                grid: .hex(0x334033, alpha: 0.4),
                defaultStroke: .hex(0xEDF7EE),
                layerColors: [
                    .hex(0xFF736D),
                    .hex(0xF0C75E),
                    .hex(0x63D88B),
                    .hex(0x4DD0C8),
                    .hex(0x83A8FF),
                    .hex(0xC493FF),
                    .hex(0xF6FFF6),
                    .hex(0x9EAE9F),
                    .hex(0xC7D7C8),
                ]
            )
        }
    }
}

struct RenderColor: Equatable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    var vector: SIMD4<Float> {
        SIMD4(red, green, blue, alpha)
    }

    var swiftUIColor: Color {
        Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }

    var cgColor: CGColor {
        CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    var storageValue: String {
        String(
            format: "%02X%02X%02X%02X",
            Self.byte(red),
            Self.byte(green),
            Self.byte(blue),
            Self.byte(alpha)
        )
    }

    init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        #if os(macOS)
        let nativeColor = NSColor(color)
        let rgbColor = nativeColor.usingColorSpace(.sRGB) ?? nativeColor
        self.init(
            red: Float(rgbColor.redComponent),
            green: Float(rgbColor.greenComponent),
            blue: Float(rgbColor.blueComponent),
            alpha: Float(rgbColor.alphaComponent)
        )
        #else
        let nativeColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        nativeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Float(red), green: Float(green), blue: Float(blue), alpha: Float(alpha))
        #endif
    }

    static func hex(_ value: Int, alpha: Float = 1.0) -> RenderColor {
        RenderColor(
            red: Float((value >> 16) & 0xff) / 255.0,
            green: Float((value >> 8) & 0xff) / 255.0,
            blue: Float(value & 0xff) / 255.0,
            alpha: alpha
        )
    }

    static func fromStorageValue(_ value: String) -> RenderColor? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard (trimmed.count == 6 || trimmed.count == 8),
              let packed = UInt32(trimmed, radix: 16) else {
            return nil
        }

        let hasAlpha = trimmed.count == 8
        let red = hasAlpha ? (packed >> 24) & 0xff : (packed >> 16) & 0xff
        let green = hasAlpha ? (packed >> 16) & 0xff : (packed >> 8) & 0xff
        let blue = hasAlpha ? (packed >> 8) & 0xff : packed & 0xff
        let alpha = hasAlpha ? packed & 0xff : 0xff

        return RenderColor(
            red: Float(red) / 255.0,
            green: Float(green) / 255.0,
            blue: Float(blue) / 255.0,
            alpha: Float(alpha) / 255.0
        )
    }

    static func hsb(hue: Float, saturation: Float, brightness: Float) -> RenderColor {
        let sector = hue * 6.0
        let integer = floor(sector)
        let fraction = sector - integer
        let p = brightness * (1.0 - saturation)
        let q = brightness * (1.0 - saturation * fraction)
        let t = brightness * (1.0 - saturation * (1.0 - fraction))

        switch Int(integer) % 6 {
        case 0: return RenderColor(red: brightness, green: t, blue: p, alpha: 1.0)
        case 1: return RenderColor(red: q, green: brightness, blue: p, alpha: 1.0)
        case 2: return RenderColor(red: p, green: brightness, blue: t, alpha: 1.0)
        case 3: return RenderColor(red: p, green: q, blue: brightness, alpha: 1.0)
        case 4: return RenderColor(red: t, green: p, blue: brightness, alpha: 1.0)
        default: return RenderColor(red: brightness, green: p, blue: q, alpha: 1.0)
        }
    }

    private static func byte(_ value: Float) -> Int {
        min(255, max(0, Int((value * 255).rounded())))
    }
}

struct DXFRenderPalette: Equatable {
    let name: String
    let background: RenderColor
    let grid: RenderColor
    let defaultStroke: RenderColor
    let layerColors: [RenderColor]

    static let standardLight = PalettePreset.studio.palette(for: .light)
    static let standardDark = PalettePreset.studio.palette(for: .dark)

    var previewColors: [RenderColor] {
        [background, defaultStroke] + layerColors
    }

    var editableColors: [RenderColor] {
        [background, grid, defaultStroke] + layerColors
    }

    var storageValue: String {
        editableColors.map(\.storageValue).joined(separator: ",")
    }

    func color(for colorIndex: Int?) -> SIMD4<Float> {
        guard let colorIndex else {
            return defaultStroke.vector
        }

        let absoluteIndex = abs(colorIndex)
        if (1...layerColors.count).contains(absoluteIndex) {
            return layerColors[absoluteIndex - 1].vector
        }

        let hue = Float((absoluteIndex * 37) % 360) / 360.0
        return RenderColor.hsb(hue: hue, saturation: 0.56, brightness: 0.92).vector
    }

    func swiftUIColor(for colorIndex: Int?) -> Color {
        let color = color(for: colorIndex)
        return Color(red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: Double(color.w))
    }

    func applyingStoredColors(_ storageValue: String) -> DXFRenderPalette {
        let colors = storageValue
            .split(separator: ",")
            .compactMap { RenderColor.fromStorageValue(String($0)) }

        guard !colors.isEmpty else { return self }

        return colors.enumerated().reduce(self) { palette, color in
            palette.replacingColor(at: color.offset, with: color.element)
        }
    }

    func color(atEditableIndex index: Int) -> RenderColor {
        let colors = editableColors
        guard colors.indices.contains(index) else {
            return defaultStroke
        }

        return colors[index]
    }

    func replacingColor(at index: Int, with color: RenderColor) -> DXFRenderPalette {
        guard index >= 0 else { return self }

        var background = self.background
        var grid = self.grid
        var defaultStroke = self.defaultStroke
        var layerColors = self.layerColors

        switch index {
        case 0:
            background = color
        case 1:
            grid = color
        case 2:
            defaultStroke = color
        default:
            let layerIndex = index - 3
            guard layerColors.indices.contains(layerIndex) else { return self }
            layerColors[layerIndex] = color
        }

        return DXFRenderPalette(
            name: name,
            background: background,
            grid: grid,
            defaultStroke: defaultStroke,
            layerColors: layerColors
        )
    }
}

struct DXFRenderStyle: Equatable {
    static let defaultLineThickness: Double = 2.5
    static let defaultTextFontName = DrawingTextFontPreset.nationalPark.rawValue

    var palette: DXFRenderPalette
    var lineThickness: Float
    var showsGridMarks: Bool
    var textFontName: String
    var contentInsets: ViewportInsets

    init(
        palette: DXFRenderPalette = .standardDark,
        lineThickness: Float = Float(DXFRenderStyle.defaultLineThickness),
        showsGridMarks: Bool = true,
        textFontName: String = DXFRenderStyle.defaultTextFontName,
        contentInsets: ViewportInsets = .zero
    ) {
        self.palette = palette
        self.lineThickness = min(12.0, max(0.5, lineThickness))
        self.showsGridMarks = showsGridMarks
        self.textFontName = Self.normalizedTextFontName(textFontName)
        self.contentInsets = contentInsets
    }

    static func normalizedTextFontName(_ fontName: String) -> String {
        let trimmed = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTextFontName : trimmed
    }

    func withContentInsets(_ contentInsets: ViewportInsets) -> DXFRenderStyle {
        DXFRenderStyle(
            palette: palette,
            lineThickness: lineThickness,
            showsGridMarks: showsGridMarks,
            textFontName: textFontName,
            contentInsets: contentInsets
        )
    }
}
