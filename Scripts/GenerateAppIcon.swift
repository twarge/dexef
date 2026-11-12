// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

// Writes the app icon as an Icon Composer bundle:
//
//     swift Scripts/GenerateAppIcon.swift
//
// The output is DeXeF/AppIcon.icon: icon.json plus one SVG per layer. Xcode's
// asset compiler turns it into every size each platform needs and applies the
// system shape and the glass, dark, clear and tinted treatments, so the
// artwork here is full bleed and carries no mask, rim or shadow of its own.
//
// The picture is a cone on a blueprint, in layers from back to front: the
// navy ground (the fill in icon.json), the drafting grid (Grid), the axes,
// hidden edge and dimension lines (Construction), the gold reference mark
// (Mark) and the cone itself (Cone).
//
// The bundle is committed, so this only needs running when the design
// changes. To look at the result without building:
//
//     "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
//         DeXeF/AppIcon.icon --export-image --output-file icon.png \
//         --platform macOS --rendition Default --width 512 --height 512 --scale 2

import Foundation

// MARK: Colours

let ink = "#F4FBFF"            // the cone's silhouette
let cyan = "#6FE7FF"           // the edge of its base
let gold = "#F6C35B"           // reference mark
let line = "#B7E6FF"           // grid and construction lines, drawn translucent
let groundTop = (0x12, 0x38, 0x5A)
let groundBottom = (0x07, 0x16, 0x25)
let darkGroundTop = (0x0C, 0x26, 0x3E)
let darkGroundBottom = (0x04, 0x0D, 0x17)

// MARK: Geometry, on the 1024 x 1024 canvas with y downward

// The drawing sits on the grid: the axis is the centre line, and the apex,
// the base and both ends of the base land on grid lines.
let gridMajor = 128.0
let gridMinor = 32.0

let axisX = 512.0
let apexY = 288.0
let baseY = 704.0
let baseRadiusX = 256.0
let baseRadiusY = 68.0
let left = axisX - baseRadiusX
let right = axisX + baseRadiusX

// The dimension lines stand off to the right of the cone and below it, and
// the reference mark sits above the upright one.
let dimensionX = 832.0
let dimensionY = 816.0

let coneWidth = 34.0
let baseWidth = 25.0
let thin = 11.0

// MARK: SVG

func n(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
}

func svg(_ body: [String]) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\n"
        + body.map { "  \($0)\n" }.joined() + "</svg>\n"
}

func segment(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> String {
    "M\(n(x1)) \(n(y1))L\(n(x2)) \(n(y2))"
}

/// Half of the base ellipse, from its left end to its right: the upper half,
/// which is the edge in view, or the lower one, which the cone hides.
func baseArc(upper: Bool) -> String {
    "M\(n(left)) \(n(baseY))A\(n(baseRadiusX)) \(n(baseRadiusY)) 0 0 \(upper ? 1 : 0) \(n(right)) \(n(baseY))"
}

/// A dashed line as separate segments, centred so that both ends finish on a
/// full dash.
func dashes(from a: (Double, Double), to b: (Double, Double), dash: Double, gap: Double) -> String {
    let length = hypot(b.0 - a.0, b.1 - a.1)
    let count = max(1, Int(((length + gap) / (dash + gap)).rounded()))
    let pitch = (length - dash) / Double(max(1, count - 1))
    let ux = (b.0 - a.0) / length
    let uy = (b.1 - a.1) / length
    return (0..<count).map { index in
        let start = Double(index) * pitch
        return segment(a.0 + ux * start, a.1 + uy * start, a.0 + ux * (start + dash), a.1 + uy * (start + dash))
    }.joined()
}

/// A dimension line with a tick across each end.
func dimension(from a: (Double, Double), to b: (Double, Double), tick: Double) -> String {
    let horizontal = a.1 == b.1
    let dx = horizontal ? 0 : tick
    let dy = horizontal ? tick : 0
    return segment(a.0, a.1, b.0, b.1)
        + segment(a.0 - dx, a.1 - dy, a.0 + dx, a.1 + dy)
        + segment(b.0 - dx, b.1 - dy, b.0 + dx, b.1 + dy)
}

func stroke(_ path: String, color: String, width: Double, opacity: Double = 1) -> String {
    "<path d=\"\(path)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(n(width))\""
        + (opacity < 1 ? " stroke-opacity=\"\(n(opacity))\"" : "")
        + " stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
}

// MARK: Layers

func cone() -> [String] {
    [
        stroke("M\(n(left)) \(n(baseY))L\(n(axisX)) \(n(apexY))L\(n(right)) \(n(baseY))", color: ink, width: coneWidth),
        stroke(baseArc(upper: true), color: cyan, width: baseWidth),
    ]
}

func mark() -> [String] {
    ["<circle cx=\"\(n(dimensionX))\" cy=\"192\" r=\"46\" fill=\"none\" stroke=\"\(gold)\" stroke-width=\"17\"/>"]
}

func construction() -> [String] {
    let paths = [
        // The cone's axis and the plane of its base.
        dashes(from: (axisX, 224), to: (axisX, 792), dash: 22, gap: 21),
        dashes(from: (192, baseY), to: (dimensionX, baseY), dash: 22, gap: 21),
        // The edge of the base that the cone hides.
        baseArc(upper: false),
        // Width and height.
        dimension(from: (left, dimensionY), to: (right, dimensionY), tick: 44),
        dimension(from: (dimensionX, baseY), to: (dimensionX, apexY), tick: 38),
    ]
    return [stroke(paths.joined(), color: line, width: thin, opacity: 0.45)]
}

func grid() -> [String] {
    func lines(every spacing: Double, skipping skipped: Double?) -> String {
        stride(from: spacing, to: 1024, by: spacing)
            .filter { position in skipped.map { position.truncatingRemainder(dividingBy: $0) != 0 } ?? true }
            .map { segment($0, 0, $0, 1024) + segment(0, $0, 1024, $0) }
            .joined()
    }
    return [
        stroke(lines(every: gridMinor, skipping: gridMajor), color: line, width: 1.5, opacity: 0.1),
        stroke(lines(every: gridMajor, skipping: nil), color: line, width: 2.5, opacity: 0.3),
    ]
}

// MARK: Bundle

struct Layer {
    let name: String
    let body: [String]
    let glass: Bool
    let shadow: Double
}

// From front to back, the order icon.json lists them. The cone and the mark
// are the glass pieces; the linework behind them stays flat.
let layers = [
    Layer(name: "Cone", body: cone(), glass: true, shadow: 0.5),
    Layer(name: "Mark", body: mark(), glass: true, shadow: 0.5),
    Layer(name: "Construction", body: construction(), glass: false, shadow: 0),
    Layer(name: "Grid", body: grid(), glass: false, shadow: 0),
]

func gradient(_ top: (Int, Int, Int), _ bottom: (Int, Int, Int)) -> [String: Any] {
    func color(_ rgb: (Int, Int, Int)) -> String {
        String(format: "extended-srgb:%.5f,%.5f,%.5f,1.00000",
               Double(rgb.0) / 255, Double(rgb.1) / 255, Double(rgb.2) / 255)
    }
    return ["linear-gradient": [color(top), color(bottom)]]
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bundle = root.appendingPathComponent("DeXeF/AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")

do {
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

    var groups: [[String: Any]] = []
    for layer in layers {
        try svg(layer.body).write(to: assets.appendingPathComponent("\(layer.name).svg"), atomically: true, encoding: .utf8)
        var entry: [String: Any] = ["image-name": "\(layer.name).svg", "name": layer.name]
        if !layer.glass {
            entry["glass"] = false
        }
        groups.append([
            "layers": [entry],
            "shadow": ["kind": "neutral", "opacity": layer.shadow],
            "translucency": ["enabled": false, "value": 0.5],
        ])
    }

    // The ground stays blueprint navy in the dark appearance, a shade deeper,
    // rather than giving way to the system's charcoal.
    let document: [String: Any] = [
        "fill-specializations": [
            ["value": gradient(groundTop, groundBottom)],
            ["appearance": "dark", "value": gradient(darkGroundTop, darkGroundBottom)],
        ],
        "groups": groups,
        "supported-platforms": ["squares": "shared"],
    ]
    var json = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    json.append(0x0A)
    try json.write(to: bundle.appendingPathComponent("icon.json"))
    print("wrote DeXeF/AppIcon.icon")
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
