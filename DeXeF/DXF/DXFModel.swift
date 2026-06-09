// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import simd
import SwiftUI

struct DXFScene {
    static let empty = DXFScene(layers: [], primitives: [], unit: .unitless)

    let id = UUID()
    let layers: [DXFLayer]
    let primitives: [DXFPrimitive]
    let unit: DXFUnit
}

enum DXFUnit: Equatable {
    case unitless
    case inches
    case feet
    case miles
    case millimeters
    case centimeters
    case meters
    case kilometers
    case microinches
    case mils
    case yards
    case angstroms
    case nanometers
    case microns
    case decimeters
    case decameters
    case hectometers
    case gigameters
    case astronomicalUnits
    case lightYears
    case parsecs
    case usSurveyFeet
    case usSurveyInches
    case usSurveyYards
    case usSurveyMiles
    case unknown(Int)

    init(insunitsCode: Int?) {
        switch insunitsCode {
        case 1: self = .inches
        case 2: self = .feet
        case 3: self = .miles
        case 4: self = .millimeters
        case 5: self = .centimeters
        case 6: self = .meters
        case 7: self = .kilometers
        case 8: self = .microinches
        case 9: self = .mils
        case 10: self = .yards
        case 11: self = .angstroms
        case 12: self = .nanometers
        case 13: self = .microns
        case 14: self = .decimeters
        case 15: self = .decameters
        case 16: self = .hectometers
        case 17: self = .gigameters
        case 18: self = .astronomicalUnits
        case 19: self = .lightYears
        case 20: self = .parsecs
        case 21: self = .usSurveyFeet
        case 22: self = .usSurveyInches
        case 23: self = .usSurveyYards
        case 24: self = .usSurveyMiles
        case let code? where code != 0:
            self = .unknown(code)
        default:
            self = .unitless
        }
    }

    var abbreviation: String? {
        switch self {
        case .unitless:
            return nil
        case .inches:
            return "in"
        case .feet:
            return "ft"
        case .miles:
            return "mi"
        case .millimeters:
            return "mm"
        case .centimeters:
            return "cm"
        case .meters:
            return "m"
        case .kilometers:
            return "km"
        case .microinches:
            return "uin"
        case .mils:
            return "mil"
        case .yards:
            return "yd"
        case .angstroms:
            return "A"
        case .nanometers:
            return "nm"
        case .microns:
            return "um"
        case .decimeters:
            return "dm"
        case .decameters:
            return "dam"
        case .hectometers:
            return "hm"
        case .gigameters:
            return "Gm"
        case .astronomicalUnits:
            return "AU"
        case .lightYears:
            return "ly"
        case .parsecs:
            return "pc"
        case .usSurveyFeet:
            return "survey ft"
        case .usSurveyInches:
            return "survey in"
        case .usSurveyYards:
            return "survey yd"
        case .usSurveyMiles:
            return "survey mi"
        case let .unknown(code):
            return "unit \(code)"
        }
    }

    var metersPerUnit: Double? {
        switch self {
        case .unitless, .unknown(_):
            return nil
        case .inches:
            return 0.0254
        case .feet:
            return 0.3048
        case .miles:
            return 1609.344
        case .millimeters:
            return 0.001
        case .centimeters:
            return 0.01
        case .meters:
            return 1
        case .kilometers:
            return 1000
        case .microinches:
            return 0.0000000254
        case .mils:
            return 0.0000254
        case .yards:
            return 0.9144
        case .angstroms:
            return 1e-10
        case .nanometers:
            return 1e-9
        case .microns:
            return 1e-6
        case .decimeters:
            return 0.1
        case .decameters:
            return 10
        case .hectometers:
            return 100
        case .gigameters:
            return 1e9
        case .astronomicalUnits:
            return 149_597_870_700
        case .lightYears:
            return 9.4607304725808e15
        case .parsecs:
            return 3.085677581491367e16
        case .usSurveyFeet:
            return 1200.0 / 3937.0
        case .usSurveyInches:
            return 100.0 / 3937.0
        case .usSurveyYards:
            return 3600.0 / 3937.0
        case .usSurveyMiles:
            return 6_336_000.0 / 3937.0
        }
    }

    func converted(_ value: Double, to targetUnit: DXFUnit) -> Double? {
        guard let sourceMeters = metersPerUnit,
              let targetMeters = targetUnit.metersPerUnit else {
            return nil
        }
        return value * sourceMeters / targetMeters
    }
}

enum CoordinateDisplayUnit: String, CaseIterable, Identifiable {
    case drawing
    case millimeters
    case centimeters
    case meters
    case kilometers
    case inches
    case feet
    case yards
    case miles
    case mils
    case microns
    case nanometers
    case angstroms
    case microinches
    case usSurveyFeet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drawing: return "Drawing Units"
        case .millimeters: return "Millimeters"
        case .centimeters: return "Centimeters"
        case .meters: return "Meters"
        case .kilometers: return "Kilometers"
        case .inches: return "Inches"
        case .feet: return "Feet"
        case .yards: return "Yards"
        case .miles: return "Miles"
        case .mils: return "Mils"
        case .microns: return "Microns"
        case .nanometers: return "Nanometers"
        case .angstroms: return "Angstroms"
        case .microinches: return "Microinches"
        case .usSurveyFeet: return "US Survey Feet"
        }
    }

    var targetUnit: DXFUnit? {
        switch self {
        case .drawing: return nil
        case .millimeters: return .millimeters
        case .centimeters: return .centimeters
        case .meters: return .meters
        case .kilometers: return .kilometers
        case .inches: return .inches
        case .feet: return .feet
        case .yards: return .yards
        case .miles: return .miles
        case .mils: return .mils
        case .microns: return .microns
        case .nanometers: return .nanometers
        case .angstroms: return .angstroms
        case .microinches: return .microinches
        case .usSurveyFeet: return .usSurveyFeet
        }
    }

    static func stored(_ rawValue: String) -> CoordinateDisplayUnit {
        CoordinateDisplayUnit(rawValue: rawValue) ?? .drawing
    }

    func displayValue(_ value: Float, from sourceUnit: DXFUnit) -> Double {
        guard let targetUnit,
              let convertedValue = sourceUnit.converted(Double(value), to: targetUnit) else {
            return Double(value)
        }
        return convertedValue
    }

    func displayAbbreviation(from sourceUnit: DXFUnit) -> String? {
        guard let targetUnit,
              sourceUnit.converted(1, to: targetUnit) != nil else {
            return sourceUnit.abbreviation
        }
        return targetUnit.abbreviation
    }
}

struct DXFLayer: Identifiable, Hashable {
    var id: String { name }

    let name: String
    let colorIndex: Int?
    let isVisibleByDefault: Bool
    let primitiveCount: Int
}

struct DXFPrimitive: Identifiable {
    let id = UUID()
    let layerName: String
    let colorIndex: Int?
    let trueColor: SIMD4<Float>?
    let isSelectable: Bool
    let kind: DXFPrimitiveKind

    init(
        layerName: String,
        colorIndex: Int?,
        trueColor: SIMD4<Float>? = nil,
        isSelectable: Bool = true,
        kind: DXFPrimitiveKind
    ) {
        self.layerName = layerName
        self.colorIndex = colorIndex
        self.trueColor = trueColor
        self.isSelectable = isSelectable && kind.isSelectableByDefault
        self.kind = kind
    }
}

enum DXFPrimitiveKind {
    case point(center: SIMD2<Float>)
    case line(start: SIMD2<Float>, end: SIMD2<Float>)
    case polyline(points: [SIMD2<Float>], isClosed: Bool)
    case curve(DXFCurve)
    case hatchFill(boundaryLoops: [[SIMD2<Float>]])
    case circle(center: SIMD2<Float>, radius: Float)
    case arc(center: SIMD2<Float>, radius: Float, startAngle: Float, endAngle: Float)
    case text(DXFText)
}

private extension DXFPrimitiveKind {
    var isSelectableByDefault: Bool {
        switch self {
        case .text, .hatchFill:
            return false
        default:
            return true
        }
    }
}

struct DXFCurve {
    let points: [SIMD2<Float>]
    let isClosed: Bool
    let anchors: [DXFCurveAnchor]
}

struct DXFCurveAnchor {
    let point: SIMD2<Float>
    let role: DXFCurveAnchorRole
}

enum DXFCurveAnchorRole {
    case center
    case endpoint
    case controlPoint
    case fitPoint
}

struct DXFText {
    let content: String
    let lines: [DXFTextLine]
    let isBold: Bool
    let insertion: SIMD2<Float>
    let height: Float
    let rotation: Float
    let widthFactor: Float
    let horizontalAnchor: DXFTextHorizontalAnchor
    let verticalAnchor: DXFTextVerticalAnchor

    init(
        content: String,
        insertion: SIMD2<Float>,
        height: Float,
        rotation: Float,
        widthFactor: Float,
        horizontalAnchor: DXFTextHorizontalAnchor,
        verticalAnchor: DXFTextVerticalAnchor,
        isBold: Bool = false,
        lines: [DXFTextLine]? = nil
    ) {
        let cleanedContent = Self.removingPercentControlCodes(from: content)
        let cleanedLines = lines?
            .map { DXFTextLine(content: Self.removingPercentControlCodes(from: $0.content), isBold: $0.isBold) }
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let cleanedLines, !cleanedLines.isEmpty {
            self.lines = cleanedLines
            self.content = cleanedLines.map(\.content).joined(separator: "\n")
            self.isBold = isBold || cleanedLines.contains(where: \.isBold)
        } else {
            self.content = cleanedContent
            self.isBold = isBold
            self.lines = cleanedContent
                .components(separatedBy: "\n")
                .map { DXFTextLine(content: $0, isBold: isBold) }
                .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        self.insertion = insertion
        self.height = height
        self.rotation = rotation
        self.widthFactor = widthFactor
        self.horizontalAnchor = horizontalAnchor
        self.verticalAnchor = verticalAnchor
    }

    private static func removingPercentControlCodes(from text: String) -> String {
        var cleaned = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "%",
               let control = percentControlCode(in: text, at: index) {
                cleaned += control.text
                index = control.nextIndex
                continue
            }

            cleaned.append(text[index])
            index = text.index(after: index)
        }

        return cleaned
    }

    private static func percentControlCode(
        in text: String,
        at index: String.Index
    ) -> (text: String, nextIndex: String.Index)? {
        let firstPercent = text.index(after: index)
        guard firstPercent < text.endIndex, text[firstPercent] == "%" else {
            return nil
        }

        let commandIndex = text.index(after: firstPercent)
        guard commandIndex < text.endIndex else {
            return ("", commandIndex)
        }

        let command = text[commandIndex]
        let nextIndex = text.index(after: commandIndex)
        switch command {
        case "%":
            return ("%", nextIndex)
        case "c", "C":
            return ("⌀", nextIndex)
        case "d", "D":
            return ("°", nextIndex)
        case "p", "P":
            return ("±", nextIndex)
        case "u", "U", "o", "O", "k", "K":
            return ("", nextIndex)
        default:
            if command.isNumber {
                var digitIndex = commandIndex
                var digits = ""
                while digitIndex < text.endIndex,
                      text[digitIndex].isNumber,
                      digits.count < 3 {
                    digits.append(text[digitIndex])
                    digitIndex = text.index(after: digitIndex)
                }

                if let value = UInt32(digits),
                   let scalar = UnicodeScalar(value) {
                    return (String(Character(scalar)), digitIndex)
                }
            }

            return ("", nextIndex)
        }
    }
}

struct DXFTextLine {
    let content: String
    let isBold: Bool
}

enum DXFTextHorizontalAnchor {
    case left
    case center
    case right
}

enum DXFTextVerticalAnchor {
    case baseline
    case top
    case middle
    case bottom
}

struct DXFBounds {
    var min: SIMD2<Float>
    var max: SIMD2<Float>

    var width: Float { Swift.max(max.x - min.x, 0.0001) }
    var height: Float { Swift.max(max.y - min.y, 0.0001) }
    var center: SIMD2<Float> {
        SIMD2((min.x + max.x) * 0.5, (min.y + max.y) * 0.5)
    }

    init(point: SIMD2<Float>) {
        min = point
        max = point
    }

    mutating func include(_ point: SIMD2<Float>) {
        min = SIMD2(Swift.min(min.x, point.x), Swift.min(min.y, point.y))
        max = SIMD2(Swift.max(max.x, point.x), Swift.max(max.y, point.y))
    }
}

enum DXFColor {
    static func rgba(for colorIndex: Int?) -> SIMD4<Float> {
        guard let colorIndex else {
            return SIMD4(0.86, 0.88, 0.92, 1.0)
        }

        switch abs(colorIndex) {
        case 1: return SIMD4(0.96, 0.22, 0.18, 1.0)
        case 2: return SIMD4(0.96, 0.78, 0.22, 1.0)
        case 3: return SIMD4(0.28, 0.78, 0.36, 1.0)
        case 4: return SIMD4(0.20, 0.76, 0.86, 1.0)
        case 5: return SIMD4(0.38, 0.55, 1.0, 1.0)
        case 6: return SIMD4(0.90, 0.34, 0.86, 1.0)
        case 7: return SIMD4(0.92, 0.94, 0.96, 1.0)
        case 8: return SIMD4(0.46, 0.50, 0.56, 1.0)
        case 9: return SIMD4(0.72, 0.76, 0.82, 1.0)
        default:
            let hue = Float((abs(colorIndex) * 37) % 360) / 360.0
            return hsb(hue: hue, saturation: 0.58, brightness: 0.92)
        }
    }

    static func swiftUIColor(for colorIndex: Int?) -> Color {
        let color = rgba(for: colorIndex)
        return Color(red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: Double(color.w))
    }

    private static func hsb(hue: Float, saturation: Float, brightness: Float) -> SIMD4<Float> {
        let sector = hue * 6.0
        let integer = floor(sector)
        let fraction = sector - integer
        let p = brightness * (1.0 - saturation)
        let q = brightness * (1.0 - saturation * fraction)
        let t = brightness * (1.0 - saturation * (1.0 - fraction))

        switch Int(integer) % 6 {
        case 0: return SIMD4(brightness, t, p, 1.0)
        case 1: return SIMD4(q, brightness, p, 1.0)
        case 2: return SIMD4(p, brightness, t, 1.0)
        case 3: return SIMD4(p, q, brightness, 1.0)
        case 4: return SIMD4(t, p, brightness, 1.0)
        default: return SIMD4(brightness, p, q, 1.0)
        }
    }
}
