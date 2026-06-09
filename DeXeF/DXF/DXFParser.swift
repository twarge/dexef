// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import simd

enum DXFParser {
    private static let maxHatchPatternSegments = 20_000
    private static let maxHatchPatternParallelLines = 4_000

    static func parse(_ text: String) -> DXFScene {
        let pairs = makePairs(from: text)
        let headerSettings = parseHeaderSettings(in: pairs)
        let context = headerSettings.withDimensionStyles(parseDimensionStyles(in: pairs, fallback: headerSettings.defaultDimensionStyle))
        let layerDefinitions = parseLayerDefinitions(in: pairs)
        let blockDefinitions = parseBlockDefinitions(in: pairs, context: context)
        let primitives = parseEntities(in: pairs, blockDefinitions: blockDefinitions, context: context)
        return makeScene(layerDefinitions: layerDefinitions, primitives: primitives, unit: context.unit)
    }

    private static func makePairs(from text: String) -> [DXFPair] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var pairs: [DXFPair] = []
        var index = 0
        while index + 1 < lines.count {
            let codeText = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let code = Int(codeText) {
                pairs.append(DXFPair(code: code, value: value))
            }
            index += 2
        }
        return pairs
    }

    private static func parseLayerDefinitions(in pairs: [DXFPair]) -> [DXFLayerDefinition] {
        var definitions: [DXFLayerDefinition] = []
        var seenNames: Set<String> = []
        var index = 0

        while index < pairs.count {
            guard pairs[index].isMarker("SECTION"),
                  pairs[safe: index + 1]?.code == 2,
                  pairs[index + 1].value.uppercased() == "TABLES" else {
                index += 1
                continue
            }

            index += 2
            while index < pairs.count, !pairs[index].isMarker("ENDSEC") {
                if pairs[index].isMarker("TABLE"),
                   pairs[safe: index + 1]?.code == 2,
                   pairs[index + 1].value.uppercased() == "LAYER" {
                    index += 2
                    while index < pairs.count, !pairs[index].isMarker("ENDTAB") {
                        if pairs[index].isMarker("LAYER") {
                            let record = collectRecord(from: pairs, startingAt: index)
                            if let layer = parseLayer(record.pairs), !seenNames.contains(layer.name) {
                                definitions.append(layer)
                                seenNames.insert(layer.name)
                            }
                            index = record.nextIndex
                        } else {
                            index += 1
                        }
                    }
                } else {
                    index += 1
                }
            }
        }

        return definitions
    }

    private static func parseHeaderSettings(in pairs: [DXFPair]) -> DXFHeaderSettings {
        var extMin: SIMD2<Float>?
        var extMax: SIMD2<Float>?
        var pointDisplaySize: Float?
        var insunitsCode: Int?
        var dimensionStyleName: String?
        var dimensionScale: Float?
        var dimensionArrowSize: Float?
        var dimensionExtensionOffset: Float?
        var dimensionExtensionBeyond: Float?
        var dimensionTextHeight: Float?
        var dimensionTextGap: Float?
        var dimensionLinearFactor: Float?
        var dimensionPrecision: Int?
        var dimensionToleranceEnabled: Bool?
        var dimensionToleranceUpper: Float?
        var dimensionToleranceLower: Float?
        var dimensionToleranceHeightScale: Float?
        var dimensionTolerancePrecision: Int?
        var currentVariable: String?
        var pendingX: Float?
        var index = 0

        while index < pairs.count {
            guard pairs[index].isMarker("SECTION"),
                  pairs[safe: index + 1]?.code == 2,
                  pairs[index + 1].value.uppercased() == "HEADER" else {
                index += 1
                continue
            }

            index += 2
            while index < pairs.count, !pairs[index].isMarker("ENDSEC") {
                let pair = pairs[index]
                if pair.code == 9 {
                    currentVariable = pair.value.uppercased()
                    pendingX = nil
                } else {
                    switch (currentVariable, pair.code) {
                    case ("$EXTMIN", 10):
                        pendingX = Float(pair.value)
                    case ("$EXTMIN", 20):
                        if let x = pendingX, let y = Float(pair.value) {
                            extMin = SIMD2(x, y)
                        }
                    case ("$EXTMAX", 10):
                        pendingX = Float(pair.value)
                    case ("$EXTMAX", 20):
                        if let x = pendingX, let y = Float(pair.value) {
                            extMax = SIMD2(x, y)
                        }
                    case ("$PDSIZE", 40):
                        pointDisplaySize = Float(pair.value)
                    case ("$INSUNITS", 70):
                        insunitsCode = Int(pair.value)
                    case ("$DIMSTYLE", 2):
                        dimensionStyleName = pair.value
                    case ("$DIMSCALE", 40):
                        dimensionScale = Float(pair.value)
                    case ("$DIMASZ", 40):
                        dimensionArrowSize = Float(pair.value)
                    case ("$DIMEXO", 40):
                        dimensionExtensionOffset = Float(pair.value)
                    case ("$DIMEXE", 40):
                        dimensionExtensionBeyond = Float(pair.value)
                    case ("$DIMTXT", 40):
                        dimensionTextHeight = Float(pair.value)
                    case ("$DIMGAP", 40):
                        dimensionTextGap = Float(pair.value)
                    case ("$DIMLFAC", 40):
                        dimensionLinearFactor = Float(pair.value)
                    case ("$DIMDEC", 70):
                        dimensionPrecision = Int(pair.value)
                    case ("$DIMTOL", 70):
                        dimensionToleranceEnabled = (Int(pair.value) ?? 0) != 0
                    case ("$DIMTP", 40):
                        dimensionToleranceUpper = Float(pair.value)
                    case ("$DIMTM", 40):
                        dimensionToleranceLower = Float(pair.value)
                    case ("$DIMTFAC", 40):
                        dimensionToleranceHeightScale = Float(pair.value)
                    case ("$DIMTDEC", 70):
                        dimensionTolerancePrecision = Int(pair.value)
                    default:
                        break
                    }
                }
                index += 1
            }
        }

        return DXFHeaderSettings(
            extMin: extMin,
            extMax: extMax,
            pointDisplaySize: pointDisplaySize,
            unit: DXFUnit(insunitsCode: insunitsCode),
            defaultDimensionStyle: DXFDimensionStyle(
                name: dimensionStyleName.flatMap { $0.isEmpty ? nil : $0 } ?? "STANDARD",
                scale: dimensionScale,
                arrowSize: dimensionArrowSize,
                extensionOffset: dimensionExtensionOffset,
                extensionBeyond: dimensionExtensionBeyond,
                textHeight: dimensionTextHeight,
                textGap: dimensionTextGap,
                linearFactor: dimensionLinearFactor,
                decimalPrecision: dimensionPrecision,
                toleranceEnabled: dimensionToleranceEnabled,
                toleranceUpper: dimensionToleranceUpper,
                toleranceLower: dimensionToleranceLower,
                toleranceHeightScale: dimensionToleranceHeightScale,
                tolerancePrecision: dimensionTolerancePrecision
            ),
            dimensionStyles: [:]
        )
    }

    private static func parseDimensionStyles(in pairs: [DXFPair], fallback: DXFDimensionStyle) -> [String: DXFDimensionStyle] {
        var styles: [String: DXFDimensionStyle] = [fallback.name.uppercased(): fallback]
        var index = 0

        while index < pairs.count {
            guard pairs[index].isMarker("SECTION"),
                  pairs[safe: index + 1]?.code == 2,
                  pairs[index + 1].value.uppercased() == "TABLES" else {
                index += 1
                continue
            }

            index += 2
            while index < pairs.count, !pairs[index].isMarker("ENDSEC") {
                if pairs[index].isMarker("TABLE"),
                   pairs[safe: index + 1]?.code == 2,
                   pairs[index + 1].value.uppercased() == "DIMSTYLE" {
                    index += 2
                    while index < pairs.count, !pairs[index].isMarker("ENDTAB") {
                        if pairs[index].isMarker("DIMSTYLE") {
                            let record = collectRecord(from: pairs, startingAt: index)
                            let style = parseDimensionStyle(record.pairs, fallback: fallback)
                            styles[style.name.uppercased()] = style
                            index = record.nextIndex
                        } else {
                            index += 1
                        }
                    }
                } else {
                    index += 1
                }
            }
        }

        return styles
    }

    private static func parseDimensionStyle(_ pairs: [DXFPair], fallback: DXFDimensionStyle) -> DXFDimensionStyle {
        DXFDimensionStyle(
            name: firstValue(code: 2, in: pairs).flatMap { $0.isEmpty ? nil : $0 } ?? fallback.name,
            scale: firstFloat(code: 40, in: pairs) ?? fallback.scale,
            arrowSize: firstFloat(code: 41, in: pairs) ?? fallback.arrowSize,
            extensionOffset: firstFloat(code: 42, in: pairs) ?? fallback.extensionOffset,
            extensionBeyond: firstFloat(code: 44, in: pairs) ?? fallback.extensionBeyond,
            textHeight: firstFloat(code: 140, in: pairs) ?? fallback.textHeight,
            textGap: firstFloat(code: 147, in: pairs) ?? fallback.textGap,
            linearFactor: firstFloat(code: 144, in: pairs) ?? fallback.linearFactor,
            decimalPrecision: firstValue(code: 271, in: pairs).flatMap(Int.init) ?? fallback.decimalPrecision,
            toleranceEnabled: firstValue(code: 71, in: pairs).flatMap(Int.init).map { $0 != 0 } ?? fallback.toleranceEnabled,
            toleranceUpper: firstFloat(code: 47, in: pairs) ?? fallback.toleranceUpper,
            toleranceLower: firstFloat(code: 48, in: pairs) ?? fallback.toleranceLower,
            toleranceHeightScale: firstFloat(code: 146, in: pairs) ?? fallback.toleranceHeightScale,
            tolerancePrecision: firstValue(code: 272, in: pairs).flatMap(Int.init) ?? fallback.tolerancePrecision
        )
    }

    private static func parseLayer(_ pairs: [DXFPair]) -> DXFLayerDefinition? {
        var name: String?
        var colorIndex: Int?
        var isVisible = true

        for pair in pairs {
            switch pair.code {
            case 2:
                name = pair.value.isEmpty ? nil : pair.value
            case 62:
                if let color = Int(pair.value) {
                    colorIndex = abs(color)
                    isVisible = color >= 0
                }
            default:
                continue
            }
        }

        guard let name else { return nil }
        return DXFLayerDefinition(name: name, colorIndex: colorIndex, isVisibleByDefault: isVisible)
    }

    private static func parseBlockDefinitions(in pairs: [DXFPair], context: DXFHeaderSettings) -> [String: DXFBlockDefinition] {
        var definitions: [String: DXFBlockDefinition] = [:]
        var index = 0

        while index < pairs.count {
            guard pairs[index].isMarker("SECTION"),
                  pairs[safe: index + 1]?.code == 2,
                  pairs[index + 1].value.uppercased() == "BLOCKS" else {
                index += 1
                continue
            }

            index += 2
            while index < pairs.count, !pairs[index].isMarker("ENDSEC") {
                guard pairs[index].isMarker("BLOCK") else {
                    index += 1
                    continue
                }

                let header = collectRecord(from: pairs, startingAt: index)
                let name = firstValue(code: 2, in: header.pairs) ?? firstValue(code: 3, in: header.pairs)
                let basePoint = SIMD2(
                    firstFloat(code: 10, in: header.pairs) ?? 0,
                    firstFloat(code: 20, in: header.pairs) ?? 0
                )
                var primitives: [DXFPrimitive] = []
                index = header.nextIndex

                while index < pairs.count, !pairs[index].isMarker("ENDBLK") {
                    guard pairs[index].code == 0 else {
                        index += 1
                        continue
                    }

                    let type = pairs[index].value.uppercased()
                    let record = collectRecord(from: pairs, startingAt: index)

                    if type == "POLYLINE" {
                        let result = parseClassicPolyline(header: record.pairs, pairs: pairs, startingAt: record.nextIndex)
                        primitives.append(contentsOf: result.primitives)
                        index = result.nextIndex
                        continue
                    }

                    primitives.append(contentsOf: parseEntity(type: type, pairs: record.pairs, blockDefinitions: [:], context: context))
                    index = record.nextIndex
                }

                if let name, !name.isEmpty {
                    definitions[name] = DXFBlockDefinition(name: name, basePoint: basePoint, primitives: primitives)
                }

                if index < pairs.count, pairs[index].isMarker("ENDBLK") {
                    index = collectRecord(from: pairs, startingAt: index).nextIndex
                }
            }
        }

        return definitions
    }

    private static func parseEntities(
        in pairs: [DXFPair],
        blockDefinitions: [String: DXFBlockDefinition],
        context: DXFHeaderSettings
    ) -> [DXFPrimitive] {
        var primitives: [DXFPrimitive] = []
        var index = 0

        while index < pairs.count {
            guard pairs[index].isMarker("SECTION"),
                  pairs[safe: index + 1]?.code == 2,
                  pairs[index + 1].value.uppercased() == "ENTITIES" else {
                index += 1
                continue
            }

            index += 2
            while index < pairs.count, !pairs[index].isMarker("ENDSEC") {
                guard pairs[index].code == 0 else {
                    index += 1
                    continue
                }

                let type = pairs[index].value.uppercased()
                let record = collectRecord(from: pairs, startingAt: index)

                if type == "POLYLINE" {
                    let result = parseClassicPolyline(header: record.pairs, pairs: pairs, startingAt: record.nextIndex)
                    primitives.append(contentsOf: result.primitives)
                    index = result.nextIndex
                    continue
                }

                primitives.append(contentsOf: parseEntity(type: type, pairs: record.pairs, blockDefinitions: blockDefinitions, context: context))
                index = record.nextIndex
            }
        }

        return primitives
    }

    private static func parseEntity(
        type: String,
        pairs: [DXFPair],
        blockDefinitions: [String: DXFBlockDefinition],
        context: DXFHeaderSettings
    ) -> [DXFPrimitive] {
        switch type {
        case "LINE":
            return parseLine(pairs).map { [$0] } ?? []
        case "POINT":
            return parsePoint(pairs)
        case "RAY", "XLINE":
            return parseInfiniteLine(pairs, isRay: type == "RAY", context: context).map { [$0] } ?? []
        case "LWPOLYLINE":
            return parseLightweightPolyline(pairs).map { [$0] } ?? []
        case "CIRCLE":
            return parseCircle(pairs).map { [$0] } ?? []
        case "ARC":
            return parseArc(pairs).map { [$0] } ?? []
        case "ELLIPSE":
            return parseEllipse(pairs).map { [$0] } ?? []
        case "SPLINE":
            return parseSpline(pairs).map { [$0] } ?? []
        case "SOLID", "TRACE", "3DFACE":
            return parseFaceOutline(pairs).map { [$0] } ?? []
        case "HATCH":
            return parseHatch(pairs)
        case "TEXT", "MTEXT", "ATTRIB", "ATTDEF":
            return parseText(pairs, isMultiline: type == "MTEXT").map { [$0] } ?? []
        case "LEADER":
            return parsePointSequence(pairs, xCode: 10, yCode: 20).map { [$0] } ?? []
        case "MLINE":
            return parsePointSequence(pairs, xCode: 11, yCode: 21).map { [$0] } ?? []
        case "MLEADER":
            return parseMultiLeader(pairs)
        case "DIMENSION":
            return parseDimension(pairs, blockDefinitions: blockDefinitions, context: context)
        case "ARC_DIMENSION":
            return parseDimension(pairs, blockDefinitions: blockDefinitions, context: context, forcedDimensionType: 8)
        case "INSERT":
            return parseInsert(pairs, blockDefinitions: blockDefinitions)
        default:
            return []
        }
    }

    private static func parseLine(_ pairs: [DXFPair]) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        guard let x1 = firstFloat(code: 10, in: pairs),
              let y1 = firstFloat(code: 20, in: pairs),
              let x2 = firstFloat(code: 11, in: pairs),
              let y2 = firstFloat(code: 21, in: pairs) else {
            return nil
        }

        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .line(start: SIMD2(x1, y1), end: SIMD2(x2, y2))
        )
    }

    private static func parsePoint(_ pairs: [DXFPair]) -> [DXFPrimitive] {
        let common = parseCommonEntityValues(pairs)
        guard let x = firstFloat(code: 10, in: pairs),
              let y = firstFloat(code: 20, in: pairs) else {
            return []
        }

        return [
            DXFPrimitive(
                layerName: common.layerName,
                colorIndex: common.colorIndex,
                trueColor: common.trueColor,
                kind: .point(center: SIMD2(x, y))
            ),
        ]
    }

    private static func parseInfiniteLine(
        _ pairs: [DXFPair],
        isRay: Bool,
        context: DXFHeaderSettings
    ) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        guard let x = firstFloat(code: 10, in: pairs),
              let y = firstFloat(code: 20, in: pairs),
              let directionX = firstFloat(code: 11, in: pairs),
              let directionY = firstFloat(code: 21, in: pairs) else {
            return nil
        }

        let base = SIMD2(x, y)
        let direction = SIMD2(directionX, directionY)
        let length = simd_length(direction)
        guard length > 0.00001 else { return nil }

        let unit = direction / length
        let span = context.referenceSpan * 4.0
        let start = isRay ? base : base - unit * span
        let end = base + unit * span
        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .line(start: start, end: end)
        )
    }

    private static func parseLightweightPolyline(_ pairs: [DXFPair]) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        var vertices: [DXFPolylineVertex] = []
        var pendingX: Float?
        var flags = 0

        for pair in pairs {
            switch pair.code {
            case 10:
                pendingX = Float(pair.value) ?? pendingX
            case 20:
                if let x = pendingX, let y = Float(pair.value) {
                    vertices.append(DXFPolylineVertex(point: SIMD2(x, y), bulge: 0))
                    pendingX = nil
                }
            case 42:
                if let bulge = Float(pair.value), !vertices.isEmpty {
                    vertices[vertices.count - 1].bulge = bulge
                }
            case 70:
                flags = Int(pair.value) ?? flags
            default:
                continue
            }
        }

        let points = polylinePoints(from: vertices, isClosed: flags & 1 == 1)
        guard points.count >= 2 else { return nil }
        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .polyline(points: points, isClosed: false)
        )
    }

    private static func parseClassicPolyline(
        header: [DXFPair],
        pairs: [DXFPair],
        startingAt index: Int
    ) -> (primitives: [DXFPrimitive], nextIndex: Int) {
        let common = parseCommonEntityValues(header)
        let flags = Int(firstValue(code: 70, in: header) ?? "0") ?? 0
        let meshMCount = Int(firstValue(code: 71, in: header) ?? "0") ?? 0
        let meshNCount = Int(firstValue(code: 72, in: header) ?? "0") ?? 0
        var vertices: [DXFPolylineVertex] = []
        var polyfacePoints: [SIMD2<Float>] = []
        var polyfaceEdges: [(Int, Int)] = []
        var cursor = index

        while cursor < pairs.count {
            guard pairs[cursor].code == 0 else {
                cursor += 1
                continue
            }

            let type = pairs[cursor].value.uppercased()
            if type == "SEQEND" {
                if flags & 16 == 16, flags & 64 == 0 {
                    let meshPrimitives = meshPolylinePrimitives(
                        points: polyfacePoints,
                        mCount: meshMCount,
                        nCount: meshNCount,
                        closeM: flags & 1 == 1,
                        closeN: flags & 32 == 32,
                        common: common
                    )
                    if !meshPrimitives.isEmpty {
                        return (meshPrimitives, cursor + 1)
                    }
                }

                if flags & 64 == 64 || flags & 16 == 16, !polyfaceEdges.isEmpty {
                    let primitives = polyfaceEdges.compactMap { edge -> DXFPrimitive? in
                        guard polyfacePoints.indices.contains(edge.0),
                              polyfacePoints.indices.contains(edge.1) else {
                            return nil
                        }

                        return DXFPrimitive(
                            layerName: common.layerName,
                            colorIndex: common.colorIndex,
                            trueColor: common.trueColor,
                            kind: .line(start: polyfacePoints[edge.0], end: polyfacePoints[edge.1])
                        )
                    }
                    return (primitives, cursor + 1)
                }

                let points = polylinePoints(from: vertices, isClosed: flags & 1 == 1)
                return (
                    points.count >= 2
                        ? [DXFPrimitive(
                            layerName: common.layerName,
                            colorIndex: common.colorIndex,
                            trueColor: common.trueColor,
                            kind: .polyline(points: points, isClosed: false)
                        )]
                        : [],
                    cursor + 1
                )
            }

            let record = collectRecord(from: pairs, startingAt: cursor)
            if type == "VERTEX" {
                let vertexFlags = Int(firstValue(code: 70, in: record.pairs) ?? "0") ?? 0
                if vertexFlags & 128 == 128 {
                    let indices = [71, 72, 73, 74]
                        .compactMap { firstValue(code: $0, in: record.pairs).flatMap(Int.init) }
                        .map { abs($0) - 1 }
                    if indices.count >= 2 {
                        for index in 0..<indices.count {
                            polyfaceEdges.append((indices[index], indices[(index + 1) % indices.count]))
                        }
                    }
                } else if let x = firstFloat(code: 10, in: record.pairs),
                          let y = firstFloat(code: 20, in: record.pairs) {
                    polyfacePoints.append(SIMD2(x, y))
                    vertices.append(DXFPolylineVertex(
                        point: SIMD2(x, y),
                        bulge: firstFloat(code: 42, in: record.pairs) ?? 0
                    ))
                }
            }
            cursor = record.nextIndex
        }

        return ([], cursor)
    }

    private static func meshPolylinePrimitives(
        points: [SIMD2<Float>],
        mCount: Int,
        nCount: Int,
        closeM: Bool,
        closeN: Bool,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?)
    ) -> [DXFPrimitive] {
        guard mCount > 0, nCount > 0, points.count >= mCount * nCount else {
            return []
        }

        var primitives: [DXFPrimitive] = []
        func pointAt(m: Int, n: Int) -> SIMD2<Float> {
            points[n * mCount + m]
        }

        for n in 0..<nCount {
            for m in 0..<(mCount - 1) {
                primitives.append(DXFPrimitive(
                    layerName: common.layerName,
                    colorIndex: common.colorIndex,
                    trueColor: common.trueColor,
                    kind: .line(start: pointAt(m: m, n: n), end: pointAt(m: m + 1, n: n))
                ))
            }
            if closeM, mCount > 1 {
                primitives.append(DXFPrimitive(
                    layerName: common.layerName,
                    colorIndex: common.colorIndex,
                    trueColor: common.trueColor,
                    kind: .line(start: pointAt(m: mCount - 1, n: n), end: pointAt(m: 0, n: n))
                ))
            }
        }

        for m in 0..<mCount {
            for n in 0..<(nCount - 1) {
                primitives.append(DXFPrimitive(
                    layerName: common.layerName,
                    colorIndex: common.colorIndex,
                    trueColor: common.trueColor,
                    kind: .line(start: pointAt(m: m, n: n), end: pointAt(m: m, n: n + 1))
                ))
            }
            if closeN, nCount > 1 {
                primitives.append(DXFPrimitive(
                    layerName: common.layerName,
                    colorIndex: common.colorIndex,
                    trueColor: common.trueColor,
                    kind: .line(start: pointAt(m: m, n: nCount - 1), end: pointAt(m: m, n: 0))
                ))
            }
        }

        return primitives
    }

    private static func parseCircle(_ pairs: [DXFPair]) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        guard let x = firstFloat(code: 10, in: pairs),
              let y = firstFloat(code: 20, in: pairs),
              let radius = firstFloat(code: 40, in: pairs),
              radius > 0 else {
            return nil
        }

        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .circle(center: SIMD2(x, y), radius: radius)
        )
    }

    private static func parseArc(_ pairs: [DXFPair]) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        guard let x = firstFloat(code: 10, in: pairs),
              let y = firstFloat(code: 20, in: pairs),
              let radius = firstFloat(code: 40, in: pairs),
              let startAngle = firstFloat(code: 50, in: pairs),
              let endAngle = firstFloat(code: 51, in: pairs),
              radius > 0 else {
            return nil
        }

        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .arc(center: SIMD2(x, y), radius: radius, startAngle: startAngle, endAngle: endAngle)
        )
    }

    private static func parseEllipse(_ pairs: [DXFPair]) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        guard let centerX = firstFloat(code: 10, in: pairs),
              let centerY = firstFloat(code: 20, in: pairs),
              let majorX = firstFloat(code: 11, in: pairs),
              let majorY = firstFloat(code: 21, in: pairs),
              let ratio = firstFloat(code: 40, in: pairs) else {
            return nil
        }

        let points = ellipsePoints(
            center: SIMD2(centerX, centerY),
            majorAxis: SIMD2(majorX, majorY),
            ratio: ratio,
            startParameter: firstFloat(code: 41, in: pairs) ?? 0,
            endParameter: firstFloat(code: 42, in: pairs) ?? Float.pi * 2
        )
        guard points.count >= 2 else { return nil }
        let center = SIMD2(centerX, centerY)
        let isClosed = isClosedPointSequence(points)
        var anchors = [DXFCurveAnchor(point: center, role: .center)]
        if !isClosed {
            if let first = points.first {
                anchors.append(DXFCurveAnchor(point: first, role: .endpoint))
            }
            if let last = points.last {
                anchors.append(DXFCurveAnchor(point: last, role: .endpoint))
            }
        }

        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .curve(DXFCurve(points: points, isClosed: isClosed, anchors: anchors))
        )
    }

    private static func parseSpline(_ pairs: [DXFPair]) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        let flags = Int(firstValue(code: 70, in: pairs) ?? "0") ?? 0
        let isClosed = flags & 1 == 1
        let isPeriodic = flags & 2 == 2
        let degree = max(1, Int(firstValue(code: 71, in: pairs) ?? "3") ?? 3)
        let knots = floats(code: 40, in: pairs).map(Double.init)
        let weights = floats(code: 41, in: pairs).map(Double.init)
        let controlPoints = pairedPoints(xCode: 10, yCode: 20, in: pairs)
        let fitPoints = pairedPoints(xCode: 11, yCode: 21, in: pairs)

        let points: [SIMD2<Float>]
        if controlPoints.count >= 2 {
            points = splinePoints(
                controlPoints: controlPoints,
                knots: knots,
                weights: weights,
                degree: degree,
                isClosed: isClosed,
                isPeriodic: isPeriodic
            )
        } else {
            points = (isClosed || isPeriodic) ? closedPointSequence(fitPoints) : fitPoints
        }

        guard points.count >= 2 else { return nil }
        let isCurveClosed = isClosedPointSequence(points)
        var anchors: [DXFCurveAnchor] = []
        if !isCurveClosed {
            if let first = points.first {
                anchors.append(DXFCurveAnchor(point: first, role: .endpoint))
            }
            if let last = points.last {
                anchors.append(DXFCurveAnchor(point: last, role: .endpoint))
            }
        }
        anchors.append(contentsOf: controlPoints.map { DXFCurveAnchor(point: $0, role: .controlPoint) })
        if controlPoints.isEmpty {
            anchors.append(contentsOf: fitPoints.map { DXFCurveAnchor(point: $0, role: .fitPoint) })
        }

        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .curve(DXFCurve(points: points, isClosed: isCurveClosed, anchors: anchors))
        )
    }

    private static func parseFaceOutline(_ pairs: [DXFPair]) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        var points = [
            point(xCode: 10, yCode: 20, in: pairs),
            point(xCode: 11, yCode: 21, in: pairs),
            point(xCode: 12, yCode: 22, in: pairs),
            point(xCode: 13, yCode: 23, in: pairs),
        ].compactMap { $0 }

        points = points.reduce(into: []) { result, point in
            if result.last != point {
                result.append(point)
            }
        }

        guard points.count >= 2 else { return nil }
        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .polyline(points: points, isClosed: points.count > 2)
        )
    }

    private static func parseHatch(_ pairs: [DXFPair]) -> [DXFPrimitive] {
        let common = parseCommonEntityValues(pairs)
        let patternName = firstValue(code: 2, in: pairs)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isSolidFill = Int(firstValue(code: 70, in: pairs) ?? "0") == 1 || patternName == "SOLID"
        var outlinePrimitives: [DXFPrimitive] = []
        var boundaryLoops: [[SIMD2<Float>]] = []
        var cursor = 0

        while cursor < pairs.count {
            guard pairs[cursor].code == 92 else {
                cursor += 1
                continue
            }

            let pathFlags = Int(pairs[cursor].value) ?? 0
            cursor += 1

            if pathFlags & 2 == 2 {
                let result = parseHatchPolylinePath(pairs, startingAt: cursor)
                cursor = result.nextIndex
                if result.points.count >= 2 {
                    outlinePrimitives.append(DXFPrimitive(
                        layerName: common.layerName,
                        colorIndex: common.colorIndex,
                        trueColor: common.trueColor,
                        isSelectable: false,
                        kind: .polyline(points: result.points, isClosed: result.isClosed)
                    ))
                }
                if result.isClosed,
                   let loop = closedHatchLoop(from: result.points) {
                    boundaryLoops.append(loop)
                }
            } else {
                let result = parseHatchEdgePath(pairs, startingAt: cursor)
                cursor = result.nextIndex
                let outlines = result.loops.isEmpty ? result.polylines.map { ($0, false) } : result.loops.map { ($0, true) }
                outlinePrimitives.append(contentsOf: outlines.compactMap { points, isClosed in
                    guard points.count >= 2 else { return nil }
                    return DXFPrimitive(
                        layerName: common.layerName,
                        colorIndex: common.colorIndex,
                        trueColor: common.trueColor,
                        isSelectable: false,
                        kind: .polyline(points: points, isClosed: isClosed)
                    )
                })
                boundaryLoops.append(contentsOf: result.loops)
            }
        }

        guard !boundaryLoops.isEmpty else {
            return outlinePrimitives
        }

        if !isSolidFill {
            let patternLines = parseHatchPatternLines(pairs)
            let patternSegments = hatchPatternSegments(boundaryLoops: boundaryLoops, patternLines: patternLines)
            let patternPrimitives = patternSegments.map { segment in
                DXFPrimitive(
                    layerName: common.layerName,
                    colorIndex: common.colorIndex,
                    trueColor: common.trueColor,
                    isSelectable: false,
                    kind: .line(start: segment.start, end: segment.end)
                )
            }
            return patternPrimitives + outlinePrimitives
        }

        let fillPrimitive = DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            isSelectable: false,
            kind: .hatchFill(boundaryLoops: boundaryLoops)
        )
        return [fillPrimitive] + outlinePrimitives
    }

    private static func parseText(_ pairs: [DXFPair], isMultiline: Bool) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        let rawContent = textContent(in: pairs)
        let styledLines = styledTextLines(rawContent, isMultiline: isMultiline)
        let content = styledLines.map(\.content).joined(separator: isMultiline ? "\n" : " ")
        guard !content.isEmpty else { return nil }

        let alignmentX = firstFloat(code: 11, in: pairs)
        let alignmentY = firstFloat(code: 21, in: pairs)
        let insertionX = alignmentX ?? firstFloat(code: 10, in: pairs)
        let insertionY = alignmentY ?? firstFloat(code: 20, in: pairs)
        guard let x = insertionX, let y = insertionY else { return nil }

        let height = firstFloat(code: 40, in: pairs) ?? 10
        guard height > 0 else { return nil }

        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .text(DXFText(
                content: content,
                insertion: SIMD2(x, y),
                height: height,
                rotation: firstFloat(code: 50, in: pairs) ?? 0,
                widthFactor: isMultiline ? 1 : max(firstFloat(code: 41, in: pairs) ?? 1, 0.01),
                horizontalAnchor: textHorizontalAnchor(in: pairs, isMultiline: isMultiline),
                verticalAnchor: textVerticalAnchor(in: pairs, isMultiline: isMultiline),
                lines: styledLines
            ))
        )
    }

    private static func parsePointSequence(
        _ pairs: [DXFPair],
        xCode: Int,
        yCode: Int
    ) -> DXFPrimitive? {
        let common = parseCommonEntityValues(pairs)
        let points = pairedPoints(xCode: xCode, yCode: yCode, in: pairs)
        guard points.count >= 2 else { return nil }

        return DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .polyline(points: points, isClosed: false)
        )
    }

    private static func parseMultiLeader(_ pairs: [DXFPair]) -> [DXFPrimitive] {
        let common = parseCommonEntityValues(pairs)
        let candidatePointRuns = [
            pairedPoints(xCode: 10, yCode: 20, in: pairs),
            pairedPoints(xCode: 11, yCode: 21, in: pairs),
        ]

        return candidatePointRuns.compactMap { points in
            guard points.count >= 2 else { return nil }
            return DXFPrimitive(
                layerName: common.layerName,
                colorIndex: common.colorIndex,
                trueColor: common.trueColor,
                kind: .polyline(points: points, isClosed: false)
            )
        }
    }

    private static func parseDimension(
        _ pairs: [DXFPair],
        blockDefinitions: [String: DXFBlockDefinition],
        context: DXFHeaderSettings,
        forcedDimensionType: Int? = nil
    ) -> [DXFPrimitive] {
        let common = parseCommonEntityValues(pairs)
        guard let blockName = firstValue(code: 2, in: pairs),
              let block = blockDefinitions[blockName],
              !block.primitives.isEmpty else {
            return parseDimensionFallback(pairs, context: context, forcedDimensionType: forcedDimensionType)
        }

        return block.primitives.map {
            inheritingCommonValues(
                primitive: $0,
                layerName: common.layerName,
                colorIndex: common.colorIndex,
                trueColor: common.trueColor
            )
        }
    }

    private static func parseDimensionFallback(
        _ pairs: [DXFPair],
        context: DXFHeaderSettings,
        forcedDimensionType: Int? = nil
    ) -> [DXFPrimitive] {
        let common = parseCommonEntityValues(pairs)
        let style = context
            .dimensionStyle(named: firstValue(code: 3, in: pairs))
            .applyingOverrides(from: pairs)
            .resolved(referenceSpan: context.referenceSpan)
        let typeCode = Int(firstValue(code: 70, in: pairs) ?? "0") ?? 0
        let dimensionType = forcedDimensionType ?? (typeCode & 8 == 8 ? 8 : typeCode & 7)

        let generated: [DXFPrimitive]
        switch dimensionType {
        case 0:
            generated = linearDimensionPrimitives(pairs, common: common, style: style, isAligned: false)
        case 1:
            generated = linearDimensionPrimitives(pairs, common: common, style: style, isAligned: true)
        case 2:
            generated = angularDimensionPrimitives(pairs, common: common, style: style, isThreePoint: false)
        case 3:
            generated = diameterDimensionPrimitives(pairs, common: common, style: style)
        case 4:
            generated = radiusDimensionPrimitives(pairs, common: common, style: style)
        case 5:
            generated = angularDimensionPrimitives(pairs, common: common, style: style, isThreePoint: true)
        case 6:
            generated = ordinateDimensionPrimitives(pairs, common: common, style: style, isXType: typeCode & 64 == 64)
        case 8:
            generated = arcLengthDimensionPrimitives(pairs, common: common, style: style)
        default:
            generated = []
        }

        if !generated.isEmpty {
            return generated
        }

        return legacyDimensionFallback(pairs, common: common)
    }

    private static func legacyDimensionFallback(
        _ pairs: [DXFPair],
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?)
    ) -> [DXFPrimitive] {
        var primitives: [DXFPrimitive] = []

        let pointPairs = [
            (13, 23, 14, 24),
            (10, 20, 11, 21),
        ]
        for pair in pointPairs {
            guard let start = point(xCode: pair.0, yCode: pair.1, in: pairs),
                  let end = point(xCode: pair.2, yCode: pair.3, in: pairs) else {
                continue
            }
            primitives.append(DXFPrimitive(
                layerName: common.layerName,
                colorIndex: common.colorIndex,
                trueColor: common.trueColor,
                kind: .line(start: start, end: end)
            ))
        }

        return primitives
    }

    private static func linearDimensionPrimitives(
        _ pairs: [DXFPair],
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle,
        isAligned: Bool
    ) -> [DXFPrimitive] {
        guard let firstExtensionPoint = point(xCode: 13, yCode: 23, in: pairs),
              let secondExtensionPoint = point(xCode: 14, yCode: 24, in: pairs) else {
            return []
        }

        let measuredVector = secondExtensionPoint - firstExtensionPoint
        let measuredLength = simd_length(measuredVector)
        guard measuredLength > 0.00001 else { return [] }

        let measuredDirection = measuredVector / measuredLength
        let dimensionDirection: SIMD2<Float>
        if isAligned {
            dimensionDirection = measuredDirection
        } else if let rotation = firstFloat(code: 50, in: pairs) {
            dimensionDirection = unitVector(angleDegrees: rotation)
        } else {
            dimensionDirection = measuredDirection
        }

        let dimensionLinePoint = point(xCode: 10, yCode: 20, in: pairs)
            ?? ((firstExtensionPoint + secondExtensionPoint) * 0.5 + perpendicular(dimensionDirection) * style.textHeight * 3)
        let extensionDirection = extensionDirection(for: pairs, dimensionDirection: dimensionDirection)
        let firstDimensionPoint = lineIntersection(
            origin: firstExtensionPoint,
            direction: extensionDirection,
            otherOrigin: dimensionLinePoint,
            otherDirection: dimensionDirection
        ) ?? projectedPoint(firstExtensionPoint, ontoLineOrigin: dimensionLinePoint, direction: dimensionDirection)
        let secondDimensionPoint = lineIntersection(
            origin: secondExtensionPoint,
            direction: extensionDirection,
            otherOrigin: dimensionLinePoint,
            otherDirection: dimensionDirection
        ) ?? projectedPoint(secondExtensionPoint, ontoLineOrigin: dimensionLinePoint, direction: dimensionDirection)

        guard let lineDirection = normalized(secondDimensionPoint - firstDimensionPoint) else { return [] }

        var primitives: [DXFPrimitive] = []
        appendLine(firstDimensionPoint, secondDimensionPoint, common: common, to: &primitives)
        appendExtensionLine(from: firstExtensionPoint, to: firstDimensionPoint, style: style, common: common, to: &primitives)
        appendExtensionLine(from: secondExtensionPoint, to: secondDimensionPoint, style: style, common: common, to: &primitives)
        appendArrowhead(tip: firstDimensionPoint, shaftDirection: lineDirection, style: style, common: common, to: &primitives)
        appendArrowhead(tip: secondDimensionPoint, shaftDirection: -lineDirection, style: style, common: common, to: &primitives)

        let measuredValue = firstFloat(code: 42, in: pairs)
            ?? (isAligned ? measuredLength : abs(simd_dot(measuredVector, dimensionDirection)))
        let midpoint = (firstDimensionPoint + secondDimensionPoint) * 0.5
        let measuredMidpoint = (firstExtensionPoint + secondExtensionPoint) * 0.5
        let textNormal = normalized(midpoint - measuredMidpoint) ?? perpendicular(lineDirection)
        let textPoint = point(xCode: 11, yCode: 21, in: pairs)
            ?? (midpoint + textNormal * (style.textHeight * 0.5 + style.textGap))
        appendDimensionText(
            rawText: firstValue(code: 1, in: pairs),
            measurement: measuredValue,
            prefix: "",
            insertion: textPoint,
            rotation: readableTextRotation(angleDegrees(for: lineDirection)),
            style: style,
            common: common,
            to: &primitives
        )

        return primitives
    }

    private static func radiusDimensionPrimitives(
        _ pairs: [DXFPair],
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle
    ) -> [DXFPrimitive] {
        guard let center = point(xCode: 10, yCode: 20, in: pairs),
              let chordPoint = point(xCode: 15, yCode: 25, in: pairs),
              let direction = normalized(chordPoint - center) else {
            return []
        }

        var primitives: [DXFPrimitive] = []
        let radius = firstFloat(code: 42, in: pairs) ?? simd_distance(center, chordPoint)
        let textPoint = point(xCode: 11, yCode: 21, in: pairs)
            ?? (chordPoint + direction * (style.textHeight + style.textGap))

        if isExternalDimensionText(textPoint, center: center, radius: radius, style: style) {
            appendExternalDimensionLeader(
                rawText: firstValue(code: 1, in: pairs),
                measurement: radius,
                prefix: "R",
                tip: chordPoint,
                textPoint: textPoint,
                radialDirection: direction,
                leaderLength: firstFloat(code: 40, in: pairs),
                style: style,
                common: common,
                to: &primitives
            )
            return primitives
        }

        appendLine(center, chordPoint, common: common, to: &primitives)
        appendArrowhead(tip: chordPoint, shaftDirection: -direction, style: style, common: common, to: &primitives)
        appendDimensionText(
            rawText: firstValue(code: 1, in: pairs),
            measurement: radius,
            prefix: "R",
            insertion: textPoint,
            rotation: readableTextRotation(angleDegrees(for: direction)),
            style: style,
            common: common,
            to: &primitives
        )

        return primitives
    }

    private static func diameterDimensionPrimitives(
        _ pairs: [DXFPair],
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle
    ) -> [DXFPrimitive] {
        guard let firstPoint = point(xCode: 15, yCode: 25, in: pairs),
              let secondPoint = point(xCode: 10, yCode: 20, in: pairs),
              let direction = normalized(secondPoint - firstPoint) else {
            return []
        }

        var primitives: [DXFPrimitive] = []
        let diameter = firstFloat(code: 42, in: pairs) ?? simd_distance(firstPoint, secondPoint)
        let center = (firstPoint + secondPoint) * 0.5
        let radius = max(diameter * 0.5, 0.0001)
        let textPoint = point(xCode: 11, yCode: 21, in: pairs)
            ?? ((firstPoint + secondPoint) * 0.5 + perpendicular(direction) * (style.textHeight + style.textGap))

        if isExternalDimensionText(textPoint, center: center, radius: radius, style: style) {
            let tip = simd_distance(textPoint, firstPoint) <= simd_distance(textPoint, secondPoint)
                ? firstPoint
                : secondPoint
            appendExternalDimensionLeader(
                rawText: firstValue(code: 1, in: pairs),
                measurement: diameter,
                prefix: "dia ",
                tip: tip,
                textPoint: textPoint,
                radialDirection: normalized(tip - center),
                leaderLength: firstFloat(code: 40, in: pairs),
                style: style,
                common: common,
                to: &primitives
            )
            return primitives
        }

        appendLine(firstPoint, secondPoint, common: common, to: &primitives)
        appendArrowhead(tip: firstPoint, shaftDirection: direction, style: style, common: common, to: &primitives)
        appendArrowhead(tip: secondPoint, shaftDirection: -direction, style: style, common: common, to: &primitives)
        appendDimensionText(
            rawText: firstValue(code: 1, in: pairs),
            measurement: diameter,
            prefix: "dia ",
            insertion: textPoint,
            rotation: readableTextRotation(angleDegrees(for: direction)),
            style: style,
            common: common,
            to: &primitives
        )

        return primitives
    }

    private static func ordinateDimensionPrimitives(
        _ pairs: [DXFPair],
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle,
        isXType: Bool
    ) -> [DXFPrimitive] {
        guard let featurePoint = point(xCode: 13, yCode: 23, in: pairs),
              let leaderEnd = point(xCode: 14, yCode: 24, in: pairs) else {
            return []
        }

        let origin = point(xCode: 10, yCode: 20, in: pairs) ?? .zero
        let measuredValue = firstFloat(code: 42, in: pairs)
            ?? (isXType ? featurePoint.x - origin.x : featurePoint.y - origin.y)
        let baselineAxis = isXType ? SIMD2<Float>(0, 1) : SIMD2<Float>(1, 0)
        let shelfAxis = SIMD2<Float>(1, 0)
        let label = dimensionLabel(rawText: firstValue(code: 1, in: pairs), measurement: measuredValue, prefix: "", style: style)
        let labelWidth = label.map { dimensionLabelWidth($0, style: style) } ?? style.textHeight
        let providedTextPoint = point(xCode: 11, yCode: 21, in: pairs)
        let baselineProjection = projectedPoint(leaderEnd, ontoLineOrigin: featurePoint, direction: baselineAxis)
        let baselineSide = signedSide(simd_dot(leaderEnd - featurePoint, baselineAxis))
        let levelOffset = simd_distance(leaderEnd, baselineProjection)
        let diagonalRun = levelOffset * 0.5
        let diagonalStart = baselineProjection - baselineAxis * baselineSide * diagonalRun
        let textLevelSide = signedSide(leaderEnd.y - featurePoint.y)
        let shelfSide = providedTextPoint
            .map { signedSide(simd_dot($0 - leaderEnd, shelfAxis)) }
            ?? signedSide(simd_dot(leaderEnd - featurePoint, shelfAxis))
        let textPoint = providedTextPoint
            ?? (leaderEnd
                + shelfAxis * shelfSide * (labelWidth * 0.5 + style.textGap)
                + SIMD2<Float>(0, textLevelSide * (style.textHeight * 0.5 + style.textGap)))
        let textOffset = abs(simd_dot(textPoint - leaderEnd, shelfAxis))
        let shelfLength = max(
            style.textHeight * 1.25,
            textOffset + labelWidth * 0.5 + style.textGap * 0.5
        )
        let shelfEnd = leaderEnd + shelfAxis * shelfSide * shelfLength

        var primitives: [DXFPrimitive] = []
        if simd_distance(featurePoint, diagonalStart) > 0.00001 {
            appendLine(featurePoint, diagonalStart, common: common, to: &primitives)
        }
        if simd_distance(diagonalStart, leaderEnd) > 0.00001 {
            appendLine(diagonalStart, leaderEnd, common: common, to: &primitives)
        }
        if simd_distance(leaderEnd, shelfEnd) > 0.00001 {
            appendLine(leaderEnd, shelfEnd, common: common, to: &primitives)
        }
        if let label, style.textHeight > 0 {
            appendDimensionLabel(
                label,
                insertion: textPoint,
                rotation: readableTextRotation(angleDegrees(for: shelfAxis * shelfSide)),
                style: style,
                common: common,
                to: &primitives
            )
        }

        return primitives
    }

    private static func angularDimensionPrimitives(
        _ pairs: [DXFPair],
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle,
        isThreePoint: Bool
    ) -> [DXFPrimitive] {
        if isThreePoint {
            guard let angleVertex = point(xCode: 13, yCode: 23, in: pairs),
                  let firstPoint = point(xCode: 14, yCode: 24, in: pairs),
                  let secondPoint = point(xCode: 15, yCode: 25, in: pairs) else {
                return []
            }
            return threePointAngularDimensionPrimitives(
                pairs,
                vertex: secondPoint,
                firstPoint: angleVertex,
                secondPoint: firstPoint,
                arcPoint: point(xCode: 10, yCode: 20, in: pairs),
                common: common,
                style: style
            )
        } else {
            guard let firstLineStart = point(xCode: 13, yCode: 23, in: pairs),
                  let firstLineEnd = point(xCode: 14, yCode: 24, in: pairs),
                  let secondLineStart = point(xCode: 10, yCode: 20, in: pairs),
                  let secondLineEnd = point(xCode: 15, yCode: 25, in: pairs) else {
                return []
            }
            return twoLineAngularDimensionPrimitives(
                pairs,
                firstLineStart: firstLineStart,
                firstLineEnd: firstLineEnd,
                secondLineStart: secondLineStart,
                secondLineEnd: secondLineEnd,
                arcPoint: point(xCode: 16, yCode: 26, in: pairs),
                common: common,
                style: style
            )
        }
    }

    private static func twoLineAngularDimensionPrimitives(
        _ pairs: [DXFPair],
        firstLineStart: SIMD2<Float>,
        firstLineEnd: SIMD2<Float>,
        secondLineStart: SIMD2<Float>,
        secondLineEnd: SIMD2<Float>,
        arcPoint: SIMD2<Float>?,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle
    ) -> [DXFPrimitive] {
        guard let firstLineDirection = normalized(firstLineEnd - firstLineStart),
              let secondLineDirection = normalized(secondLineEnd - secondLineStart) else {
            return []
        }

        let vertex = lineIntersection(
            origin: firstLineStart,
            direction: firstLineDirection,
            otherOrigin: secondLineStart,
            otherDirection: secondLineDirection
        ) ?? closestPointBetweenLines(
            firstStart: firstLineStart,
            firstEnd: firstLineEnd,
            secondStart: secondLineStart,
            secondEnd: secondLineEnd
        )

        let targetDirection = arcPoint.flatMap { normalized($0 - vertex) }
        let rays = selectedAngularLineRays(
            firstLineStart: firstLineStart,
            firstLineEnd: firstLineEnd,
            firstDirection: firstLineDirection,
            secondLineStart: secondLineStart,
            secondLineEnd: secondLineEnd,
            secondDirection: secondLineDirection,
            vertex: vertex,
            targetDirection: targetDirection
        )

        return curvedDimensionPrimitives(
            pairs,
            center: vertex,
            firstDirection: rays.firstDirection,
            secondDirection: rays.secondDirection,
            sweep: rays.sweep,
            firstFeaturePoint: rays.firstFeaturePoint,
            secondFeaturePoint: rays.secondFeaturePoint,
            arcPoint: arcPoint,
            measuredValue: firstFloat(code: 42, in: pairs) ?? abs(rays.sweep) * 180 / .pi,
            appliesLinearFactor: false,
            common: common,
            style: style
        )
    }

    private static func threePointAngularDimensionPrimitives(
        _ pairs: [DXFPair],
        vertex: SIMD2<Float>,
        firstPoint: SIMD2<Float>,
        secondPoint: SIMD2<Float>,
        arcPoint: SIMD2<Float>?,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle
    ) -> [DXFPrimitive] {
        guard let firstDirection = normalized(firstPoint - vertex),
              let secondDirection = normalized(secondPoint - vertex) else {
            return []
        }

        let targetDirection = arcPoint.flatMap { normalized($0 - vertex) }
        let sweep = angularSweepRadians(
            from: angleRadians(for: firstDirection),
            to: angleRadians(for: secondDirection),
            through: targetDirection.map(angleRadians(for:))
        )

        return curvedDimensionPrimitives(
            pairs,
            center: vertex,
            firstDirection: firstDirection,
            secondDirection: secondDirection,
            sweep: sweep,
            firstFeaturePoint: firstPoint,
            secondFeaturePoint: secondPoint,
            arcPoint: arcPoint,
            measuredValue: firstFloat(code: 42, in: pairs) ?? abs(sweep) * 180 / .pi,
            appliesLinearFactor: false,
            common: common,
            style: style
        )
    }

    private static func arcLengthDimensionPrimitives(
        _ pairs: [DXFPair],
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle
    ) -> [DXFPrimitive] {
        guard let center = point(xCode: 15, yCode: 25, in: pairs) ?? point(xCode: 10, yCode: 20, in: pairs),
              let firstPoint = point(xCode: 13, yCode: 23, in: pairs),
              let secondPoint = point(xCode: 14, yCode: 24, in: pairs) else {
            return []
        }

        let firstDirection: SIMD2<Float>
        let secondDirection: SIMD2<Float>
        let measuredRadius: Float

        if let startAngle = firstFloat(code: 50, in: pairs),
           let endAngle = firstFloat(code: 51, in: pairs) {
            firstDirection = unitVector(angleDegrees: startAngle)
            secondDirection = unitVector(angleDegrees: endAngle)
            measuredRadius = max(simd_distance(center, firstPoint), simd_distance(center, secondPoint), style.arrowSize)
        } else {
            guard let startDirection = normalized(firstPoint - center),
                  let endDirection = normalized(secondPoint - center) else {
                return []
            }
            firstDirection = startDirection
            secondDirection = endDirection
            measuredRadius = max((simd_distance(center, firstPoint) + simd_distance(center, secondPoint)) * 0.5, style.arrowSize)
        }

        let arcPoint = point(xCode: 16, yCode: 26, in: pairs) ?? point(xCode: 10, yCode: 20, in: pairs)
        let targetDirection = arcPoint.flatMap { normalized($0 - center) }
        let sweep = angularSweepRadians(
            from: angleRadians(for: firstDirection),
            to: angleRadians(for: secondDirection),
            through: targetDirection.map(angleRadians(for:))
        )
        guard abs(sweep) > 0.00001 else { return [] }

        return curvedDimensionPrimitives(
            pairs,
            center: center,
            firstDirection: firstDirection,
            secondDirection: secondDirection,
            sweep: sweep,
            firstFeaturePoint: firstPoint,
            secondFeaturePoint: secondPoint,
            arcPoint: arcPoint,
            measuredValue: firstFloat(code: 42, in: pairs) ?? measuredRadius * abs(sweep),
            appliesLinearFactor: true,
            common: common,
            style: style
        )
    }

    private static func curvedDimensionPrimitives(
        _ pairs: [DXFPair],
        center: SIMD2<Float>,
        firstDirection: SIMD2<Float>,
        secondDirection: SIMD2<Float>,
        sweep: Float,
        firstFeaturePoint: SIMD2<Float>,
        secondFeaturePoint: SIMD2<Float>,
        arcPoint: SIMD2<Float>?,
        measuredValue: Float,
        appliesLinearFactor: Bool,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        style: DXFResolvedDimensionStyle
    ) -> [DXFPrimitive] {
        let firstDistance = simd_distance(center, firstFeaturePoint)
        let secondDistance = simd_distance(center, secondFeaturePoint)
        let fallbackRadius = max(minPositive(firstDistance, secondDistance) ?? max(firstDistance, secondDistance), style.arrowSize * 2)
        let dimensionRadius = max(arcPoint.map { simd_distance(center, $0) } ?? fallbackRadius * 0.75, style.arrowSize * 2)
        guard dimensionRadius > 0.00001, abs(sweep) > 0.00001 else { return [] }

        let firstAngle = angleRadians(for: firstDirection)
        let arcPoints = arcPoints(center: center, radius: dimensionRadius, startRadians: firstAngle, sweepRadians: sweep)
        guard arcPoints.count >= 2 else { return [] }

        var primitives: [DXFPrimitive] = []
        appendRadialExtensionLine(
            center: center,
            direction: firstDirection,
            featurePoint: firstFeaturePoint,
            dimensionRadius: dimensionRadius,
            style: style,
            common: common,
            to: &primitives
        )
        appendRadialExtensionLine(
            center: center,
            direction: secondDirection,
            featurePoint: secondFeaturePoint,
            dimensionRadius: dimensionRadius,
            style: style,
            common: common,
            to: &primitives
        )
        primitives.append(DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .polyline(points: arcPoints, isClosed: false)
        ))

        let sweepSign: Float = sweep >= 0 ? 1 : -1
        appendArrowhead(
            tip: arcPoints[0],
            shaftDirection: perpendicular(firstDirection) * sweepSign,
            style: style,
            common: common,
            to: &primitives
        )
        appendArrowhead(
            tip: arcPoints[arcPoints.count - 1],
            shaftDirection: -perpendicular(secondDirection) * sweepSign,
            style: style,
            common: common,
            to: &primitives
        )

        let midAngle = firstAngle + sweep * 0.5
        let midDirection = SIMD2(cos(midAngle), sin(midAngle))
        let textPoint = point(xCode: 11, yCode: 21, in: pairs)
            ?? (center + midDirection * (dimensionRadius + style.textHeight + style.textGap))
        let textRadialDirection = normalized(textPoint - center) ?? midDirection
        let textTangentDirection = perpendicular(textRadialDirection) * sweepSign
        appendDimensionText(
            rawText: firstValue(code: 1, in: pairs),
            measurement: measuredValue,
            prefix: "",
            insertion: textPoint,
            rotation: readableTextRotation(angleDegrees(for: textTangentDirection)),
            appliesLinearFactor: appliesLinearFactor,
            style: style,
            common: common,
            to: &primitives
        )

        return primitives
    }

    private static func selectedAngularLineRays(
        firstLineStart: SIMD2<Float>,
        firstLineEnd: SIMD2<Float>,
        firstDirection: SIMD2<Float>,
        secondLineStart: SIMD2<Float>,
        secondLineEnd: SIMD2<Float>,
        secondDirection: SIMD2<Float>,
        vertex: SIMD2<Float>,
        targetDirection: SIMD2<Float>?
    ) -> (
        firstDirection: SIMD2<Float>,
        secondDirection: SIMD2<Float>,
        firstFeaturePoint: SIMD2<Float>,
        secondFeaturePoint: SIMD2<Float>,
        sweep: Float
    ) {
        let targetAngle = targetDirection.map { angleRadians(for: $0) }
        let firstDirections = [firstDirection, -firstDirection]
        let secondDirections = [secondDirection, -secondDirection]
        var best: (
            firstDirection: SIMD2<Float>,
            secondDirection: SIMD2<Float>,
            firstFeaturePoint: SIMD2<Float>,
            secondFeaturePoint: SIMD2<Float>,
            sweep: Float,
            score: Float
        )?

        for firstCandidate in firstDirections {
            for secondCandidate in secondDirections {
                let startAngle = angleRadians(for: firstCandidate)
                let endAngle = angleRadians(for: secondCandidate)
                let sweep = angularSweepRadians(from: startAngle, to: endAngle, through: targetAngle)
                guard abs(sweep) > 0.00001 else { continue }

                var score = abs(sweep)
                if let targetAngle, !angle(targetAngle, isInsideSweepFrom: startAngle, sweep: sweep) {
                    score += Float.pi * 2
                }

                let firstFeaturePoint = angularFeaturePoint(
                    start: firstLineStart,
                    end: firstLineEnd,
                    vertex: vertex,
                    direction: firstCandidate
                )
                let secondFeaturePoint = angularFeaturePoint(
                    start: secondLineStart,
                    end: secondLineEnd,
                    vertex: vertex,
                    direction: secondCandidate
                )
                if simd_dot(firstFeaturePoint - vertex, firstCandidate) < -0.00001 {
                    score += 0.25
                }
                if simd_dot(secondFeaturePoint - vertex, secondCandidate) < -0.00001 {
                    score += 0.25
                }

                if best == nil || score < best!.score {
                    best = (
                        firstCandidate,
                        secondCandidate,
                        firstFeaturePoint,
                        secondFeaturePoint,
                        sweep,
                        score
                    )
                }
            }
        }

        if let best {
            return (
                best.firstDirection,
                best.secondDirection,
                best.firstFeaturePoint,
                best.secondFeaturePoint,
                best.sweep
            )
        }

        let fallbackSweep = angularSweepRadians(
            from: angleRadians(for: firstDirection),
            to: angleRadians(for: secondDirection),
            through: targetAngle
        )
        return (
            firstDirection,
            secondDirection,
            firstLineEnd,
            secondLineEnd,
            fallbackSweep
        )
    }

    private static func angularFeaturePoint(
        start: SIMD2<Float>,
        end: SIMD2<Float>,
        vertex: SIMD2<Float>,
        direction: SIMD2<Float>
    ) -> SIMD2<Float> {
        let startProjection = simd_dot(start - vertex, direction)
        let endProjection = simd_dot(end - vertex, direction)

        if startProjection >= 0, endProjection >= 0 {
            return startProjection >= endProjection ? start : end
        }
        if startProjection >= 0 {
            return start
        }
        if endProjection >= 0 {
            return end
        }
        return abs(startProjection) <= abs(endProjection) ? start : end
    }

    private static func appendRadialExtensionLine(
        center: SIMD2<Float>,
        direction: SIMD2<Float>,
        featurePoint: SIMD2<Float>,
        dimensionRadius: Float,
        style: DXFResolvedDimensionStyle,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        to primitives: inout [DXFPrimitive]
    ) {
        guard let direction = normalized(direction) else { return }

        let featureDistance = max(simd_dot(featurePoint - center, direction), 0)
        let startDistance: Float
        let endDistance: Float

        if featureDistance <= dimensionRadius {
            startDistance = min(featureDistance + style.extensionOffset, dimensionRadius)
            endDistance = dimensionRadius + style.extensionBeyond
        } else {
            startDistance = max(dimensionRadius - style.extensionBeyond, 0)
            endDistance = max(featureDistance - style.extensionOffset, startDistance)
        }

        guard endDistance - startDistance > 0.00001 else { return }
        appendLine(
            center + direction * startDistance,
            center + direction * endDistance,
            common: common,
            to: &primitives
        )
    }

    private static func angularSweepRadians(
        from startAngle: Float,
        to endAngle: Float,
        through targetAngle: Float?
    ) -> Float {
        let counterClockwise = positiveSweepRadians(from: startAngle, to: endAngle)
        let clockwise = counterClockwise - Float.pi * 2

        if let targetAngle {
            let containsCounterClockwise = angle(targetAngle, isInsideSweepFrom: startAngle, sweep: counterClockwise)
            let containsClockwise = angle(targetAngle, isInsideSweepFrom: startAngle, sweep: clockwise)
            if containsCounterClockwise != containsClockwise {
                return containsCounterClockwise ? counterClockwise : clockwise
            }
        }

        return abs(counterClockwise) <= abs(clockwise) ? counterClockwise : clockwise
    }

    private static func angle(_ angle: Float, isInsideSweepFrom startAngle: Float, sweep: Float) -> Bool {
        let epsilon: Float = 0.0001
        if sweep >= 0 {
            return positiveSweepRadians(from: startAngle, to: angle) <= sweep + epsilon
        }
        return positiveSweepRadians(from: angle, to: startAngle) <= abs(sweep) + epsilon
    }

    private static func positiveSweepRadians(from startAngle: Float, to endAngle: Float) -> Float {
        var sweep = (endAngle - startAngle).truncatingRemainder(dividingBy: Float.pi * 2)
        if sweep < 0 {
            sweep += Float.pi * 2
        }
        return sweep
    }

    private static func closestPointBetweenLines(
        firstStart: SIMD2<Float>,
        firstEnd: SIMD2<Float>,
        secondStart: SIMD2<Float>,
        secondEnd: SIMD2<Float>
    ) -> SIMD2<Float> {
        ((firstStart + firstEnd) + (secondStart + secondEnd)) * 0.25
    }

    private static func minPositive(_ first: Float, _ second: Float) -> Float? {
        [first, second].filter { $0 > 0.00001 }.min()
    }

    private static func appendExtensionLine(
        from definitionPoint: SIMD2<Float>,
        to dimensionPoint: SIMD2<Float>,
        style: DXFResolvedDimensionStyle,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        to primitives: inout [DXFPrimitive]
    ) {
        let vector = dimensionPoint - definitionPoint
        let length = simd_length(vector)
        guard length > 0.00001 else { return }

        let direction = vector / length
        let offset = min(style.extensionOffset, length * 0.8)
        appendLine(
            definitionPoint + direction * offset,
            dimensionPoint + direction * style.extensionBeyond,
            common: common,
            to: &primitives
        )
    }

    private static func appendArrowhead(
        tip: SIMD2<Float>,
        shaftDirection: SIMD2<Float>,
        style: DXFResolvedDimensionStyle,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        to primitives: inout [DXFPrimitive]
    ) {
        guard style.arrowSize > 0,
              let direction = normalized(shaftDirection) else {
            return
        }

        let normal = perpendicular(direction)
        let base = tip + direction * style.arrowSize
        let wing = style.arrowSize * 0.38
        appendLine(tip, base + normal * wing, common: common, to: &primitives)
        appendLine(tip, base - normal * wing, common: common, to: &primitives)
    }

    private static func appendDimensionText(
        rawText: String?,
        measurement: Float,
        prefix: String,
        insertion: SIMD2<Float>,
        rotation: Float,
        appliesLinearFactor: Bool = true,
        style: DXFResolvedDimensionStyle,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        to primitives: inout [DXFPrimitive]
    ) {
        guard let label = dimensionLabel(rawText: rawText, measurement: measurement, prefix: prefix, appliesLinearFactor: appliesLinearFactor, style: style),
              style.textHeight > 0 else {
            return
        }

        appendDimensionLabel(
            label,
            insertion: insertion,
            rotation: rotation,
            style: style,
            common: common,
            to: &primitives
        )
    }

    private static func appendDimensionLabel(
        _ label: DXFDimensionLabel,
        insertion: SIMD2<Float>,
        rotation: Float,
        style: DXFResolvedDimensionStyle,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        to primitives: inout [DXFPrimitive]
    ) {
        guard !label.main.isEmpty else { return }

        guard let upperTolerance = label.upperTolerance,
              let lowerTolerance = label.lowerTolerance else {
            appendTextPrimitive(
                label.main,
                insertion: insertion,
                height: style.textHeight,
                rotation: rotation,
                horizontalAnchor: .center,
                verticalAnchor: .middle,
                common: common,
                to: &primitives
            )
            return
        }

        let radians = rotation * .pi / 180
        let tangent = SIMD2(cos(radians), sin(radians))
        let toleranceHeight = style.textHeight * style.toleranceHeightScale
        let labelGap = max(style.textGap * 0.35, style.textHeight * 0.12)
        let mainWidth = estimatedTextWidth(label.main, height: style.textHeight)
        let toleranceText = "\(upperTolerance)\n\(lowerTolerance)"
        let toleranceWidth = estimatedTextWidth(toleranceText, height: toleranceHeight)
        let totalWidth = mainWidth + labelGap + toleranceWidth
        let mainInsertion = insertion - tangent * ((totalWidth - mainWidth) * 0.5)
        let toleranceInsertion = insertion + tangent * ((totalWidth - toleranceWidth) * 0.5)

        appendTextPrimitive(
            label.main,
            insertion: mainInsertion,
            height: style.textHeight,
            rotation: rotation,
            horizontalAnchor: .center,
            verticalAnchor: .middle,
            common: common,
            to: &primitives
        )
        appendTextPrimitive(
            toleranceText,
            insertion: toleranceInsertion,
            height: toleranceHeight,
            rotation: rotation,
            horizontalAnchor: .center,
            verticalAnchor: .middle,
            common: common,
            to: &primitives
        )
    }

    private static func appendTextPrimitive(
        _ content: String,
        insertion: SIMD2<Float>,
        height: Float,
        rotation: Float,
        horizontalAnchor: DXFTextHorizontalAnchor,
        verticalAnchor: DXFTextVerticalAnchor,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        to primitives: inout [DXFPrimitive]
    ) {
        guard !content.isEmpty, height > 0 else { return }

        primitives.append(DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .text(DXFText(
                content: content,
                insertion: insertion,
                height: height,
                rotation: rotation,
                widthFactor: 1,
                horizontalAnchor: horizontalAnchor,
                verticalAnchor: verticalAnchor
            ))
        ))
    }

    private static func appendExternalDimensionLeader(
        rawText: String?,
        measurement: Float,
        prefix: String,
        tip: SIMD2<Float>,
        textPoint: SIMD2<Float>,
        radialDirection: SIMD2<Float>?,
        leaderLength: Float?,
        style: DXFResolvedDimensionStyle,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        to primitives: inout [DXFPrimitive]
    ) {
        let label = dimensionLabel(rawText: rawText, measurement: measurement, prefix: prefix, style: style)
        let labelWidth = label.map { dimensionLabelWidth($0, style: style) } ?? style.textHeight
        let textSide = horizontalLeaderSide(textPoint: textPoint, tip: tip, radialDirection: radialDirection)
        let leaderGap = max(style.textGap, style.arrowSize * 0.2)
        let landingLength = max(leaderLength ?? style.arrowSize * 1.25, 0)
        let leaderEnd = SIMD2(textPoint.x - textSide * (labelWidth * 0.5 + leaderGap), textPoint.y)
        let leaderStart = radialDimensionLeaderStart(
            tip: tip,
            leaderEnd: leaderEnd,
            textSide: textSide,
            radialDirection: radialDirection,
            fallbackLength: landingLength
        )

        if let leaderDirection = normalized(radialDirection ?? (leaderStart - tip)) {
            appendLine(tip, leaderStart, common: common, to: &primitives)
            if simd_distance(leaderStart, leaderEnd) > 0.00001 {
                appendLine(leaderStart, leaderEnd, common: common, to: &primitives)
            }
            appendArrowhead(tip: tip, shaftDirection: leaderDirection, style: style, common: common, to: &primitives)
        }

        if let label {
            appendDimensionLabel(
                label,
                insertion: textPoint,
                rotation: 0,
                style: style,
                common: common,
                to: &primitives
            )
        }
    }

    private static func horizontalLeaderSide(
        textPoint: SIMD2<Float>,
        tip: SIMD2<Float>,
        radialDirection: SIMD2<Float>?
    ) -> Float {
        let textDeltaX = textPoint.x - tip.x
        if abs(textDeltaX) > 0.00001 {
            return textDeltaX >= 0 ? 1 : -1
        }

        if let radialDirection, abs(radialDirection.x) > 0.00001 {
            return radialDirection.x >= 0 ? 1 : -1
        }

        return 1
    }

    private static func radialDimensionLeaderStart(
        tip: SIMD2<Float>,
        leaderEnd: SIMD2<Float>,
        textSide: Float,
        radialDirection: SIMD2<Float>?,
        fallbackLength: Float
    ) -> SIMD2<Float> {
        let fallbackStart = leaderEnd - SIMD2(textSide * fallbackLength, 0)
        guard let direction = normalized(radialDirection ?? (fallbackStart - tip)) else {
            return fallbackStart
        }

        if abs(direction.y) > 0.00001 {
            let distanceToLeaderY = (leaderEnd.y - tip.y) / direction.y
            if distanceToLeaderY >= 0 {
                return tip + direction * distanceToLeaderY
            }
        }

        return fallbackStart
    }

    private static func appendLine(
        _ start: SIMD2<Float>,
        _ end: SIMD2<Float>,
        common: (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?),
        to primitives: inout [DXFPrimitive]
    ) {
        primitives.append(DXFPrimitive(
            layerName: common.layerName,
            colorIndex: common.colorIndex,
            trueColor: common.trueColor,
            kind: .line(start: start, end: end)
        ))
    }

    private static func dimensionLabel(
        rawText: String?,
        measurement: Float,
        prefix: String,
        appliesLinearFactor: Bool = true,
        style: DXFResolvedDimensionStyle
    ) -> DXFDimensionLabel? {
        let factor = appliesLinearFactor ? style.linearFactor : 1
        let generated = prefix + formatDimensionValue(measurement * factor, precision: style.decimalPrecision)
        let mainText: String
        var explicitTolerance: (upper: String, lower: String)?
        if let rawText {
            if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }

            let explicitText = dimensionTextWithExplicitTolerance(rawText, generated: generated)
            mainText = explicitText.main
            explicitTolerance = explicitText.tolerance
        } else {
            mainText = generated
        }

        guard !mainText.isEmpty else { return nil }

        let tolerance = explicitTolerance ?? dimensionTolerance(style: style, linearFactor: factor)
        return DXFDimensionLabel(
            main: mainText,
            upperTolerance: tolerance?.upper,
            lowerTolerance: tolerance?.lower
        )
    }

    private static func dimensionTolerance(
        style: DXFResolvedDimensionStyle,
        linearFactor: Float
    ) -> (upper: String, lower: String)? {
        guard style.toleranceEnabled else { return nil }
        guard abs(style.toleranceUpper) > 0.0000001 || abs(style.toleranceLower) > 0.0000001 else {
            return nil
        }

        let upper = style.toleranceUpper * linearFactor
        let lower = style.toleranceLower * linearFactor
        return (
            toleranceText(upper, isUpper: true, precision: style.tolerancePrecision),
            toleranceText(lower, isUpper: false, precision: style.tolerancePrecision)
        )
    }

    private static func toleranceText(_ value: Float, isUpper: Bool, precision: Int) -> String {
        if isUpper {
            if value < 0 {
                return "-" + formatDimensionValue(abs(value), precision: precision)
            }
            return formatDimensionValue(value, precision: precision)
        }

        if value > 0 {
            return "-" + formatDimensionValue(value, precision: precision)
        }
        return formatDimensionValue(value, precision: precision)
    }

    private static func dimensionTextWithExplicitTolerance(
        _ rawText: String,
        generated: String
    ) -> (main: String, tolerance: (upper: String, lower: String)?) {
        let replaced = rawText.replacingOccurrences(of: "<>", with: generated)
        var remaining = replaced
        var tolerance: (upper: String, lower: String)?

        if let stack = firstStackedText(in: replaced) {
            remaining.removeSubrange(stack.range)
            tolerance = (
                cleanText(stack.upper, isMultiline: false),
                cleanText(stack.lower, isMultiline: false)
            )
        }

        return (
            cleanText(remaining, isMultiline: false),
            tolerance
        )
    }

    private static func firstStackedText(
        in text: String
    ) -> (upper: String, lower: String, range: Range<String.Index>)? {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let commandRange = nextStackedTextCommand(in: text, from: searchStart) {
            let stackStart = commandRange.upperBound
            guard let end = text[stackStart...].firstIndex(of: ";") else {
                return nil
            }

            let stackContent = String(text[stackStart..<end])
            if let separator = stackContent.firstIndex(where: { $0 == "^" || $0 == "/" || $0 == "#" }) {
                let upper = String(stackContent[..<separator])
                let lower = String(stackContent[stackContent.index(after: separator)...])
                return (
                    upper,
                    lower,
                    commandRange.lowerBound..<text.index(after: end)
                )
            }

            searchStart = text.index(after: end)
        }

        return nil
    }

    private static func nextStackedTextCommand(
        in text: String,
        from searchStart: String.Index
    ) -> Range<String.Index>? {
        var index = searchStart
        while index < text.endIndex {
            guard let escape = text[index...].firstIndex(of: "\\") else {
                return nil
            }

            let commandIndex = text.index(after: escape)
            guard commandIndex < text.endIndex else {
                return nil
            }

            if text[commandIndex] == "S" || text[commandIndex] == "s" {
                return escape..<text.index(after: commandIndex)
            }

            index = commandIndex
        }

        return nil
    }

    private static func isExternalDimensionText(
        _ textPoint: SIMD2<Float>,
        center: SIMD2<Float>,
        radius: Float,
        style: DXFResolvedDimensionStyle
    ) -> Bool {
        simd_distance(textPoint, center) > radius + max(style.textHeight * 0.6, style.textGap)
    }

    private static func dimensionLabelWidth(_ label: DXFDimensionLabel, style: DXFResolvedDimensionStyle) -> Float {
        let mainWidth = estimatedTextWidth(label.main, height: style.textHeight)
        guard let upperTolerance = label.upperTolerance,
              let lowerTolerance = label.lowerTolerance else {
            return mainWidth
        }

        let toleranceHeight = style.textHeight * style.toleranceHeightScale
        let toleranceWidth = estimatedTextWidth("\(upperTolerance)\n\(lowerTolerance)", height: toleranceHeight)
        return mainWidth + max(style.textGap * 0.35, style.textHeight * 0.12) + toleranceWidth
    }

    private static func estimatedTextWidth(_ text: String, height: Float) -> Float {
        let maxCharacterCount = text
            .components(separatedBy: "\n")
            .map { $0.count }
            .max() ?? 0
        return Float(maxCharacterCount) * height * 0.58
    }

    private static func formatDimensionValue(_ value: Float, precision: Int) -> String {
        var text = String(format: "%.\(precision)f", Double(value))
        if precision > 0 {
            while text.last == "0" {
                text.removeLast()
            }
            if text.last == "." {
                text.removeLast()
            }
        }
        return text == "-0" ? "0" : text
    }

    private static func extensionDirection(for pairs: [DXFPair], dimensionDirection: SIMD2<Float>) -> SIMD2<Float> {
        if let obliqueAngle = firstFloat(code: 52, in: pairs) {
            return unitVector(angleDegrees: angleDegrees(for: dimensionDirection) + obliqueAngle)
        }
        return perpendicular(dimensionDirection)
    }

    private static func projectedPoint(
        _ point: SIMD2<Float>,
        ontoLineOrigin origin: SIMD2<Float>,
        direction: SIMD2<Float>
    ) -> SIMD2<Float> {
        origin + direction * simd_dot(point - origin, direction)
    }

    private static func lineIntersection(
        origin: SIMD2<Float>,
        direction: SIMD2<Float>,
        otherOrigin: SIMD2<Float>,
        otherDirection: SIMD2<Float>
    ) -> SIMD2<Float>? {
        let denominator = cross(direction, otherDirection)
        guard abs(denominator) > 0.00001 else { return nil }
        let t = cross(otherOrigin - origin, otherDirection) / denominator
        return origin + direction * t
    }

    private static func normalized(_ vector: SIMD2<Float>) -> SIMD2<Float>? {
        let length = simd_length(vector)
        guard length > 0.00001 else { return nil }
        return vector / length
    }

    private static func perpendicular(_ vector: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(-vector.y, vector.x)
    }

    private static func signedSide(_ value: Float) -> Float {
        value < 0 ? -1 : 1
    }

    private static func cross(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Float {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    private static func unitVector(angleDegrees: Float) -> SIMD2<Float> {
        let radians = angleDegrees * .pi / 180
        return SIMD2(cos(radians), sin(radians))
    }

    private static func angleDegrees(for vector: SIMD2<Float>) -> Float {
        atan2(vector.y, vector.x) * 180 / .pi
    }

    private static func angleRadians(for vector: SIMD2<Float>) -> Float {
        atan2(vector.y, vector.x)
    }

    private static func readableTextRotation(_ angle: Float) -> Float {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        if normalized > 90 && normalized < 270 {
            normalized += 180
        }
        return normalized.truncatingRemainder(dividingBy: 360)
    }

    private static func shortestSweepRadians(from start: Float, to end: Float) -> Float {
        var sweep = end - start
        while sweep <= -.pi {
            sweep += .pi * 2
        }
        while sweep > .pi {
            sweep -= .pi * 2
        }
        return sweep
    }

    private static func arcPoints(
        center: SIMD2<Float>,
        radius: Float,
        startRadians: Float,
        sweepRadians: Float
    ) -> [SIMD2<Float>] {
        let steps = max(12, min(192, Int(ceil(abs(sweepRadians) / (.pi / 48)))))
        return (0...steps).map { step in
            let t = Float(step) / Float(steps)
            let angle = startRadians + sweepRadians * t
            return center + SIMD2(cos(angle), sin(angle)) * radius
        }
    }

    private static func parseInsert(
        _ pairs: [DXFPair],
        blockDefinitions: [String: DXFBlockDefinition]
    ) -> [DXFPrimitive] {
        let common = parseCommonEntityValues(pairs)
        guard let name = firstValue(code: 2, in: pairs),
              let block = blockDefinitions[name] else {
            return []
        }

        let transform = DXFInsertTransform(
            insertionPoint: SIMD2(
                firstFloat(code: 10, in: pairs) ?? 0,
                firstFloat(code: 20, in: pairs) ?? 0
            ),
            basePoint: block.basePoint,
            scale: SIMD2(
                firstFloat(code: 41, in: pairs) ?? 1,
                firstFloat(code: 42, in: pairs) ?? 1
            ),
            rotationDegrees: firstFloat(code: 50, in: pairs) ?? 0
        )

        let columnCount = max(Int(firstValue(code: 70, in: pairs) ?? "1") ?? 1, 1)
        let rowCount = max(Int(firstValue(code: 71, in: pairs) ?? "1") ?? 1, 1)
        let columnSpacing = firstFloat(code: 44, in: pairs) ?? 0
        let rowSpacing = firstFloat(code: 45, in: pairs) ?? 0
        var primitives: [DXFPrimitive] = []

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                let arrayOffset = SIMD2(Float(column) * columnSpacing, Float(row) * rowSpacing)
                let arrayTransform = transform.withAdditionalInsertionOffset(arrayOffset)
                primitives.append(contentsOf: block.primitives.map {
                    transformed(
                        primitive: $0,
                        using: arrayTransform,
                        insertLayerName: common.layerName,
                        insertColorIndex: common.colorIndex,
                        insertTrueColor: common.trueColor
                    )
                })
            }
        }

        return primitives
    }

    private static func parseHatchPolylinePath(
        _ pairs: [DXFPair],
        startingAt index: Int
    ) -> (points: [SIMD2<Float>], isClosed: Bool, nextIndex: Int) {
        var cursor = index
        var vertices: [DXFPolylineVertex] = []
        var pendingX: Float?
        var vertexCount: Int?
        var isClosed = false

        while cursor < pairs.count {
            let pair = pairs[cursor]
            if pair.code == 92 {
                break
            }
            if let vertexCount, vertices.count >= vertexCount, pair.code != 42 {
                break
            }

            switch pair.code {
            case 73 where vertexCount == nil:
                isClosed = Int(pair.value) == 1
            case 93 where vertexCount == nil:
                vertexCount = Int(pair.value)
            case 10:
                pendingX = Float(pair.value)
            case 20:
                if let x = pendingX, let y = Float(pair.value) {
                    vertices.append(DXFPolylineVertex(point: SIMD2(x, y), bulge: 0))
                    pendingX = nil
                }
            case 42:
                if let bulge = Float(pair.value), !vertices.isEmpty {
                    vertices[vertices.count - 1].bulge = bulge
                }
            default:
                break
            }

            cursor += 1
        }

        return (polylinePoints(from: vertices, isClosed: isClosed), isClosed, cursor)
    }

    private static func parseHatchEdgePath(
        _ pairs: [DXFPair],
        startingAt index: Int
    ) -> DXFHatchEdgePath {
        var cursor = index
        while cursor < pairs.count, pairs[cursor].code != 93, pairs[cursor].code != 92 {
            cursor += 1
        }

        guard cursor < pairs.count, pairs[cursor].code == 93 else {
            return DXFHatchEdgePath(polylines: [], loops: [], nextIndex: cursor)
        }

        let edgeCount = max(Int(pairs[cursor].value) ?? 0, 0)
        cursor += 1
        var polylines: [[SIMD2<Float>]] = []

        for _ in 0..<edgeCount {
            while cursor < pairs.count, pairs[cursor].code != 72, pairs[cursor].code != 92 {
                cursor += 1
            }
            guard cursor < pairs.count, pairs[cursor].code == 72 else {
                break
            }

            let edgeType = Int(pairs[cursor].value) ?? 0
            let edgeStart = cursor + 1
            cursor = edgeStart
            while cursor < pairs.count, pairs[cursor].code != 72, pairs[cursor].code != 92 {
                cursor += 1
            }

            let edgePairs = Array(pairs[edgeStart..<cursor])
            if let points = hatchEdgePoints(type: edgeType, pairs: edgePairs), points.count >= 2 {
                polylines.append(points)
            }
        }

        return DXFHatchEdgePath(
            polylines: polylines,
            loops: stitchedHatchLoops(from: polylines),
            nextIndex: cursor
        )
    }

    private static func hatchEdgePoints(type: Int, pairs: [DXFPair]) -> [SIMD2<Float>]? {
        switch type {
        case 1:
            guard let start = point(xCode: 10, yCode: 20, in: pairs),
                  let end = point(xCode: 11, yCode: 21, in: pairs) else {
                return nil
            }
            return [start, end]

        case 2:
            guard let center = point(xCode: 10, yCode: 20, in: pairs),
                  let radius = firstFloat(code: 40, in: pairs),
                  radius > 0 else {
                return nil
            }
            let startAngle = firstFloat(code: 50, in: pairs) ?? 0
            let endAngle = firstFloat(code: 51, in: pairs) ?? 360
            let isCounterClockwise = Int(firstValue(code: 73, in: pairs) ?? "1") != 0
            return hatchArcPoints(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                isCounterClockwise: isCounterClockwise
            )

        case 3:
            guard let center = point(xCode: 10, yCode: 20, in: pairs),
                  let majorX = firstFloat(code: 11, in: pairs),
                  let majorY = firstFloat(code: 21, in: pairs),
                  let ratio = firstFloat(code: 40, in: pairs) else {
                return nil
            }
            let start = (firstFloat(code: 50, in: pairs) ?? 0) * .pi / 180.0
            let end = (firstFloat(code: 51, in: pairs) ?? 360) * .pi / 180.0
            let isCounterClockwise = Int(firstValue(code: 73, in: pairs) ?? "1") != 0
            return hatchEllipsePoints(
                center: center,
                majorAxis: SIMD2(majorX, majorY),
                ratio: ratio,
                startParameter: start,
                endParameter: end,
                isCounterClockwise: isCounterClockwise
            )

        case 4:
            let controlPoints = pairedPoints(xCode: 10, yCode: 20, in: pairs)
            let fitPoints = pairedPoints(xCode: 11, yCode: 21, in: pairs)
            let knots = floats(code: 40, in: pairs).map(Double.init)
            let weights = floats(code: 42, in: pairs).map(Double.init)
            let degree = max(1, Int(firstValue(code: 94, in: pairs) ?? "3") ?? 3)
            if controlPoints.count >= 2 {
                return splinePoints(
                    controlPoints: controlPoints,
                    knots: knots,
                    weights: weights,
                    degree: degree,
                    isClosed: false,
                    isPeriodic: false
                )
            }
            return fitPoints

        default:
            return nil
        }
    }

    private static func closedHatchLoop(from points: [SIMD2<Float>]) -> [SIMD2<Float>]? {
        var loop = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard loop.count >= 3 else { return nil }

        let tolerance = hatchPointTolerance(for: loop)
        if let first = loop.first,
           let last = loop.last,
           simd_distance(first, last) > tolerance {
            loop.append(first)
        }

        return loop.count >= 4 ? loop : nil
    }

    private static func stitchedHatchLoops(from polylines: [[SIMD2<Float>]]) -> [[SIMD2<Float>]] {
        var remaining = polylines
            .map { $0.filter { $0.x.isFinite && $0.y.isFinite } }
            .filter { $0.count >= 2 }
        let tolerance = hatchPointTolerance(for: remaining.flatMap { $0 })
        var loops: [[SIMD2<Float>]] = []

        while !remaining.isEmpty {
            var loop = remaining.removeFirst()
            var didAppend = true

            while didAppend,
                  let first = loop.first,
                  let last = loop.last,
                  simd_distance(first, last) > tolerance {
                didAppend = false

                for index in remaining.indices {
                    let candidate = remaining[index]
                    guard let candidateFirst = candidate.first,
                          let candidateLast = candidate.last else {
                        continue
                    }

                    if simd_distance(last, candidateFirst) <= tolerance {
                        appendHatchPoints(candidate.dropFirst(), to: &loop, tolerance: tolerance)
                        remaining.remove(at: index)
                        didAppend = true
                        break
                    }

                    if simd_distance(last, candidateLast) <= tolerance {
                        appendHatchPoints(candidate.reversed().dropFirst(), to: &loop, tolerance: tolerance)
                        remaining.remove(at: index)
                        didAppend = true
                        break
                    }
                }
            }

            if let first = loop.first,
               let last = loop.last,
               simd_distance(first, last) <= tolerance,
               let closedLoop = closedHatchLoop(from: loop) {
                loops.append(closedLoop)
            }
        }

        return loops
    }

    private static func appendHatchPoints<S: Sequence>(
        _ newPoints: S,
        to points: inout [SIMD2<Float>],
        tolerance: Float
    ) where S.Element == SIMD2<Float> {
        for point in newPoints {
            guard let last = points.last,
                  simd_distance(last, point) <= tolerance else {
                points.append(point)
                continue
            }
        }
    }

    private static func hatchPointTolerance(for points: [SIMD2<Float>]) -> Float {
        guard var minPoint = points.first,
              var maxPoint = points.first else {
            return 0.0001
        }

        for point in points.dropFirst() {
            minPoint = SIMD2(min(minPoint.x, point.x), min(minPoint.y, point.y))
            maxPoint = SIMD2(max(maxPoint.x, point.x), max(maxPoint.y, point.y))
        }

        let span = max(maxPoint.x - minPoint.x, maxPoint.y - minPoint.y)
        return max(span * 0.00001, 0.0001)
    }

    private static func hatchArcPoints(
        center: SIMD2<Float>,
        radius: Float,
        startAngle: Float,
        endAngle: Float,
        isCounterClockwise: Bool
    ) -> [SIMD2<Float>] {
        let sweep = hatchSweep(from: startAngle, to: endAngle, isCounterClockwise: isCounterClockwise)
        let steps = max(12, min(192, Int(ceil(abs(sweep) / 8.0))))

        return (0...steps).map { step in
            let t = Float(step) / Float(steps)
            let angle = startAngle + sweep * t
            let radians = angle * .pi / 180.0
            return SIMD2(center.x + cos(radians) * radius, center.y + sin(radians) * radius)
        }
    }

    private static func hatchEllipsePoints(
        center: SIMD2<Float>,
        majorAxis: SIMD2<Float>,
        ratio: Float,
        startParameter: Float,
        endParameter: Float,
        isCounterClockwise: Bool
    ) -> [SIMD2<Float>] {
        guard simd_length(majorAxis) > 0.00001, ratio > 0 else { return [] }

        var sweep = endParameter - startParameter
        if isCounterClockwise {
            while sweep <= 0 {
                sweep += .pi * 2
            }
        } else {
            while sweep >= 0 {
                sweep -= .pi * 2
            }
        }

        let minorAxis = SIMD2(-majorAxis.y, majorAxis.x) * ratio
        let steps = max(24, min(256, Int(ceil(abs(sweep) / (.pi / 48.0)))))

        return (0...steps).map { step in
            let t = Float(step) / Float(steps)
            let parameter = startParameter + sweep * t
            return center + majorAxis * cos(parameter) + minorAxis * sin(parameter)
        }
    }

    private static func hatchSweep(from startAngle: Float, to endAngle: Float, isCounterClockwise: Bool) -> Float {
        var sweep = endAngle - startAngle
        if isCounterClockwise {
            while sweep <= 0 {
                sweep += 360
            }
        } else {
            while sweep >= 0 {
                sweep -= 360
            }
        }
        return sweep
    }

    private static func parseHatchPatternLines(_ pairs: [DXFPair]) -> [DXFHatchPatternLine] {
        guard let countIndex = pairs.firstIndex(where: { $0.code == 78 }),
              let lineCount = Int(pairs[countIndex].value),
              lineCount > 0 else {
            return []
        }

        let patternAngle = firstFloat(code: 52, in: pairs) ?? 0
        var cursor = countIndex + 1
        var patternLines: [DXFHatchPatternLine] = []

        for _ in 0..<lineCount {
            var angle: Float?
            var baseX: Float?
            var baseY: Float?
            var offsetX: Float?
            var offsetY: Float?
            var dashCount: Int?
            var dashes: [Float] = []

            while cursor < pairs.count {
                let pair = pairs[cursor]
                if pair.code == 53, angle != nil {
                    break
                }
                if pair.code == 98 || pair.code == 92 || pair.code == 0 {
                    break
                }

                switch pair.code {
                case 53:
                    angle = Float(pair.value)
                case 43:
                    baseX = Float(pair.value)
                case 44:
                    baseY = Float(pair.value)
                case 45:
                    offsetX = Float(pair.value)
                case 46:
                    offsetY = Float(pair.value)
                case 79:
                    dashCount = max(Int(pair.value) ?? 0, 0)
                case 49:
                    if dashCount == nil || dashes.count < (dashCount ?? 0),
                       let dash = Float(pair.value) {
                        dashes.append(dash)
                    }
                default:
                    break
                }

                cursor += 1
            }

            guard let angle,
                  let baseX,
                  let baseY,
                  let offsetX,
                  let offsetY else {
                continue
            }

            let rawBase = SIMD2(baseX, baseY)
            let rawOffset = SIMD2(offsetX, offsetY)
            let base = rotate(rawBase, degrees: patternAngle)
            let offset = rotate(rawOffset, degrees: patternAngle)
            patternLines.append(DXFHatchPatternLine(
                angleDegrees: angle + patternAngle,
                base: base,
                offset: offset,
                dashes: dashCount == 0 ? [] : dashes
            ))
        }

        return patternLines
    }

    private static func hatchPatternSegments(
        boundaryLoops: [[SIMD2<Float>]],
        patternLines: [DXFHatchPatternLine]
    ) -> [(start: SIMD2<Float>, end: SIMD2<Float>)] {
        guard !boundaryLoops.isEmpty, !patternLines.isEmpty else { return [] }

        var segments: [(start: SIMD2<Float>, end: SIMD2<Float>)] = []
        for patternLine in patternLines {
            appendHatchPatternSegments(
                boundaryLoops: boundaryLoops,
                patternLine: patternLine,
                segments: &segments
            )
            if segments.count >= maxHatchPatternSegments {
                break
            }
        }
        return segments
    }

    private static func appendHatchPatternSegments(
        boundaryLoops: [[SIMD2<Float>]],
        patternLine: DXFHatchPatternLine,
        segments: inout [(start: SIMD2<Float>, end: SIMD2<Float>)]
    ) {
        guard segments.count < maxHatchPatternSegments else { return }
        let allPoints = boundaryLoops.flatMap { $0 }
        guard !allPoints.isEmpty,
              simd_length(patternLine.offset) > 0.00001 else {
            return
        }

        let direction = unitVector(angleDegrees: patternLine.angleDegrees)
        let normal = SIMD2(-direction.y, direction.x)
        let spacing = simd_dot(patternLine.offset, normal)
        guard abs(spacing) > 0.00001 else { return }

        let distances = allPoints.map { simd_dot($0 - patternLine.base, normal) }
        guard let minDistance = distances.min(),
              let maxDistance = distances.max() else {
            return
        }

        let kA = minDistance / spacing
        let kB = maxDistance / spacing
        let minK = Int(floor(min(kA, kB))) - 2
        let maxK = Int(ceil(max(kA, kB))) + 2
        let lineCount = maxK - minK + 1
        guard lineCount > 0,
              lineCount <= maxHatchPatternParallelLines else {
            return
        }

        let tolerance = max(hatchPointTolerance(for: allPoints) * 0.1, 0.00001)
        for lineIndex in minK...maxK where segments.count < maxHatchPatternSegments {
            let origin = patternLine.base + patternLine.offset * Float(lineIndex)
            let intervals = hatchPatternIntervals(
                origin: origin,
                direction: direction,
                normal: normal,
                boundaryLoops: boundaryLoops,
                tolerance: tolerance
            )

            for interval in intervals where segments.count < maxHatchPatternSegments {
                appendDashSegments(
                    interval: interval,
                    origin: origin,
                    direction: direction,
                    dashes: patternLine.dashes,
                    tolerance: tolerance,
                    segments: &segments
                )
            }
        }
    }

    private static func hatchPatternIntervals(
        origin: SIMD2<Float>,
        direction: SIMD2<Float>,
        normal: SIMD2<Float>,
        boundaryLoops: [[SIMD2<Float>]],
        tolerance: Float
    ) -> [(Float, Float)] {
        var intersections: [Float] = []

        for rawLoop in boundaryLoops {
            var loop = rawLoop.filter { $0.x.isFinite && $0.y.isFinite }
            guard loop.count >= 3 else { continue }
            if let first = loop.first,
               let last = loop.last,
               simd_distance(first, last) <= tolerance {
                loop.removeLast()
            }

            for index in loop.indices {
                let start = loop[index]
                let end = loop[(index + 1) % loop.count]
                let startDistance = simd_dot(start - origin, normal)
                let endDistance = simd_dot(end - origin, normal)

                guard (startDistance <= 0 && endDistance > 0) || (endDistance <= 0 && startDistance > 0) else {
                    continue
                }

                let denominator = startDistance - endDistance
                guard abs(denominator) > 0.000001 else { continue }
                let t = startDistance / denominator
                let intersection = start + (end - start) * t
                intersections.append(simd_dot(intersection - origin, direction))
            }
        }

        let sorted = intersections.sorted()
        var unique: [Float] = []
        for value in sorted {
            if let last = unique.last, abs(last - value) <= tolerance {
                continue
            }
            unique.append(value)
        }

        var intervals: [(Float, Float)] = []
        var index = 0
        while index + 1 < unique.count {
            let start = unique[index]
            let end = unique[index + 1]
            if end - start > tolerance {
                intervals.append((start, end))
            }
            index += 2
        }

        return intervals
    }

    private static func appendDashSegments(
        interval: (Float, Float),
        origin: SIMD2<Float>,
        direction: SIMD2<Float>,
        dashes: [Float],
        tolerance: Float,
        segments: inout [(start: SIMD2<Float>, end: SIMD2<Float>)]
    ) {
        let start = min(interval.0, interval.1)
        let end = max(interval.0, interval.1)
        guard end - start > tolerance else { return }

        let dashPattern = dashes.filter { abs($0) > tolerance }
        let patternLength = dashPattern.reduce(Float(0)) { $0 + abs($1) }
        guard !dashPattern.isEmpty, patternLength > tolerance else {
            segments.append((origin + direction * start, origin + direction * end))
            return
        }

        var dashIndex = 0
        var phase = positiveRemainder(start, divisor: patternLength)
        while phase > abs(dashPattern[dashIndex]) && dashIndex < dashPattern.count - 1 {
            phase -= abs(dashPattern[dashIndex])
            dashIndex += 1
        }

        var cursor = start
        var remaining = max(abs(dashPattern[dashIndex]) - phase, tolerance)

        while cursor < end - tolerance,
              segments.count < maxHatchPatternSegments {
            let next = min(cursor + remaining, end)
            if dashPattern[dashIndex] > 0, next - cursor > tolerance {
                segments.append((origin + direction * cursor, origin + direction * next))
            }
            cursor = next
            dashIndex = (dashIndex + 1) % dashPattern.count
            remaining = max(abs(dashPattern[dashIndex]), tolerance)
        }
    }

    private static func positiveRemainder(_ value: Float, divisor: Float) -> Float {
        guard divisor > 0 else { return 0 }
        var result = value.truncatingRemainder(dividingBy: divisor)
        if result < 0 {
            result += divisor
        }
        return result
    }

    private static func rotate(_ point: SIMD2<Float>, degrees: Float) -> SIMD2<Float> {
        guard abs(degrees) > 0.00001 else { return point }
        let radians = degrees * .pi / 180
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        return SIMD2(
            point.x * cosValue - point.y * sinValue,
            point.x * sinValue + point.y * cosValue
        )
    }

    private static func textContent(in pairs: [DXFPair]) -> String {
        pairs
            .filter { $0.code == 1 || $0.code == 3 }
            .map(\.value)
            .joined()
    }

    private static func styledTextLines(_ text: String, isMultiline: Bool) -> [DXFTextLine] {
        var lines: [DXFTextLine] = []
        var current = ""
        var currentBold = false
        var lineIsBold = false
        var index = text.startIndex

        func append(_ string: String) {
            guard !string.isEmpty else { return }
            current += string
            if currentBold {
                lineIsBold = true
            }
        }

        func finishLine() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(DXFTextLine(content: trimmed, isBold: lineIsBold))
            }
            current = ""
            lineIsBold = currentBold
        }

        while index < text.endIndex {
            let character = text[index]

            if character == "%",
               let control = percentControlCode(in: text, at: index) {
                append(control.text)
                index = control.nextIndex
                continue
            }

            if character == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else {
                    index = next
                    continue
                }

                let command = text[next]
                switch command {
                case "P", "p", "X", "x":
                    if isMultiline {
                        finishLine()
                    } else {
                        append(" ")
                    }
                    index = text.index(after: next)
                    continue
                case "~":
                    append(" ")
                    index = text.index(after: next)
                    continue
                case "\\", "{", "}":
                    append(String(command))
                    index = text.index(after: next)
                    continue
                case "L", "l", "O", "o", "K", "k":
                    index = text.index(after: next)
                    continue
                case "U", "u":
                    if let unicode = unicodeEscape(in: text, at: index) {
                        append(String(unicode.character))
                        index = unicode.nextIndex
                        continue
                    }
                case "S", "s":
                    if let stack = stackedText(in: text, at: index) {
                        append(stack.text)
                        index = stack.nextIndex
                        continue
                    }
                case "F", "f":
                    let commandStart = text.index(after: next)
                    guard let commandEnd = text[commandStart...].firstIndex(of: ";") else {
                        index = text.index(after: next)
                        continue
                    }
                    if let isBold = fontCommandBoldState(String(text[commandStart..<commandEnd])) {
                        currentBold = isBold
                    }
                    index = text.index(after: commandEnd)
                    continue
                case "A", "C", "c", "H", "h", "Q", "q", "T", "t", "W", "w":
                    index = text.index(after: next)
                    while index < text.endIndex, text[index] != ";" {
                        index = text.index(after: index)
                    }
                    if index < text.endIndex {
                        index = text.index(after: index)
                    }
                    continue
                default:
                    break
                }
            }

            if character != "{" && character != "}" {
                append(String(character))
            }
            index = text.index(after: index)
        }

        finishLine()
        return lines
    }

    private static func fontCommandBoldState(_ command: String) -> Bool? {
        for rawPart in command.split(separator: "|") {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard part.lowercased().hasPrefix("b") else { continue }
            let value = part.dropFirst()
            guard let flag = Int(value) else { continue }
            return flag != 0
        }
        return nil
    }

    private static func cleanText(_ text: String, isMultiline: Bool) -> String {
        var cleaned = ""
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if character == "%",
               let control = percentControlCode(in: text, at: index) {
                cleaned += control.text
                index = control.nextIndex
                continue
            }

            if character == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else {
                    index = next
                    continue
                }

                let command = text[next]
                switch command {
                case "P", "p", "X", "x":
                    cleaned += "\n"
                    index = text.index(after: next)
                    continue
                case "~":
                    cleaned += " "
                    index = text.index(after: next)
                    continue
                case "\\", "{", "}":
                    cleaned.append(command)
                    index = text.index(after: next)
                    continue
                case "L", "l", "O", "o", "K", "k":
                    index = text.index(after: next)
                    continue
                case "U", "u":
                    if let unicode = unicodeEscape(in: text, at: index) {
                        cleaned.append(unicode.character)
                        index = unicode.nextIndex
                        continue
                    }
                case "S", "s":
                    if let stack = stackedText(in: text, at: index) {
                        cleaned += stack.text
                        index = stack.nextIndex
                        continue
                    }
                case "A", "C", "c", "F", "f", "H", "h", "Q", "q", "T", "t", "W", "w":
                    index = text.index(after: next)
                    while index < text.endIndex, text[index] != ";" {
                        index = text.index(after: index)
                    }
                    if index < text.endIndex {
                        index = text.index(after: index)
                    }
                    continue
                default:
                    break
                }
            }

            cleaned.append(character)
            index = text.index(after: index)
        }

        index = cleaned.startIndex
        while index < cleaned.endIndex {
            let character = cleaned[index]
            if character == "{" || character == "}" {
                index = cleaned.index(after: index)
                continue
            }

            result.append(character)
            index = cleaned.index(after: index)
        }

        cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if isMultiline {
            return cleaned
        }
        return cleaned.replacingOccurrences(of: "\n", with: " ")
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

    private static func unicodeEscape(
        in text: String,
        at index: String.Index
    ) -> (character: Character, nextIndex: String.Index)? {
        let uIndex = text.index(after: index)
        let plusIndex = text.index(after: uIndex)
        guard plusIndex < text.endIndex, text[plusIndex] == "+" else {
            return nil
        }

        var hexIndex = text.index(after: plusIndex)
        var hex = ""
        while hexIndex < text.endIndex,
              text[hexIndex].isHexDigit,
              hex.count < 6 {
            hex.append(text[hexIndex])
            hexIndex = text.index(after: hexIndex)
        }

        guard !hex.isEmpty,
              let value = UInt32(hex, radix: 16),
              let scalar = UnicodeScalar(value) else {
            return nil
        }

        return (Character(scalar), hexIndex)
    }

    private static func stackedText(
        in text: String,
        at index: String.Index
    ) -> (text: String, nextIndex: String.Index)? {
        let contentStart = text.index(index, offsetBy: 2)
        guard contentStart <= text.endIndex,
              let end = text[contentStart...].firstIndex(of: ";") else {
            return nil
        }

        let content = String(text[contentStart..<end])
        let separator = content.firstIndex { character in
            character == "/" || character == "#" || character == "^"
        }
        let plainText: String
        if let separator {
            var upper = String(content[..<separator])
            var lower = String(content[content.index(after: separator)...])
            upper = cleanText(upper, isMultiline: false)
            lower = cleanText(lower, isMultiline: false)
            plainText = upper.isEmpty || lower.isEmpty ? upper + lower : "\(upper)/\(lower)"
        } else {
            plainText = cleanText(content, isMultiline: false)
        }

        return (plainText, text.index(after: end))
    }

    private static func inheritingCommonValues(
        primitive: DXFPrimitive,
        layerName: String,
        colorIndex: Int?,
        trueColor: SIMD4<Float>?
    ) -> DXFPrimitive {
        DXFPrimitive(
            layerName: primitive.layerName == "0" ? layerName : primitive.layerName,
            colorIndex: primitive.colorIndex ?? colorIndex,
            trueColor: primitive.trueColor ?? trueColor,
            isSelectable: primitive.isSelectable,
            kind: primitive.kind
        )
    }

    private static func polylinePoints(from vertices: [DXFPolylineVertex], isClosed: Bool) -> [SIMD2<Float>] {
        guard vertices.count >= 2 else { return vertices.map(\.point) }

        let segmentCount = isClosed ? vertices.count : vertices.count - 1
        var points: [SIMD2<Float>] = []

        for index in 0..<segmentCount {
            let current = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            appendPoints(
                bulgedSegmentPoints(from: current.point, to: next.point, bulge: current.bulge),
                to: &points
            )
        }

        return points
    }

    private static func bulgedSegmentPoints(
        from start: SIMD2<Float>,
        to end: SIMD2<Float>,
        bulge: Float
    ) -> [SIMD2<Float>] {
        let chord = end - start
        let chordLength = simd_length(chord)
        guard abs(bulge) > 0.00001, chordLength > 0.00001 else {
            return [start, end]
        }

        let theta = 4.0 * atan(bulge)
        let midpoint = (start + end) * 0.5
        let normal = SIMD2(-chord.y / chordLength, chord.x / chordLength)
        let centerOffset = chordLength * (1.0 - bulge * bulge) / (4.0 * bulge)
        let center = midpoint + normal * centerOffset
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let radius = simd_length(start - center)
        let steps = max(4, min(96, Int(ceil(abs(theta) / (.pi / 24.0)))))

        return (0...steps).map { step in
            let t = Float(step) / Float(steps)
            let angle = startAngle + theta * t
            return SIMD2(center.x + cos(angle) * radius, center.y + sin(angle) * radius)
        }
    }

    private static func ellipsePoints(
        center: SIMD2<Float>,
        majorAxis: SIMD2<Float>,
        ratio: Float,
        startParameter: Float,
        endParameter: Float
    ) -> [SIMD2<Float>] {
        guard simd_length(majorAxis) > 0.00001, ratio > 0 else { return [] }

        var sweep = endParameter - startParameter
        while sweep <= 0 {
            sweep += .pi * 2
        }

        let minorAxis = SIMD2(-majorAxis.y, majorAxis.x) * ratio
        let steps = max(24, min(256, Int(ceil(abs(sweep) / (.pi / 48.0)))))

        return (0...steps).map { step in
            let t = Float(step) / Float(steps)
            let parameter = startParameter + sweep * t
            return center + majorAxis * cos(parameter) + minorAxis * sin(parameter)
        }
    }

    private static func splinePoints(
        controlPoints: [SIMD2<Float>],
        knots: [Double],
        weights: [Double],
        degree: Int,
        isClosed: Bool,
        isPeriodic: Bool
    ) -> [SIMD2<Float>] {
        guard controlPoints.count >= 2 else { return controlPoints }

        let hasWrappedControlPoints = repeatedControlPointPrefixCount(
            in: controlPoints,
            degree: degree
        ) >= degree
        let isImplicitlyClosed = !isClosed
            && !isPeriodic
            && hasWrappedControlPoints
            && !isClampedKnotVector(knots, degree: degree)
        let shouldCloseSamples = isClosed || isPeriodic || isImplicitlyClosed

        if degree <= 1 || knots.count != controlPoints.count + degree + 1 {
            return shouldCloseSamples ? closedPointSequence(controlPoints) : controlPoints
        }

        let usesPeriodicClosure = shouldAddPeriodicSplineControlPoints(
            controlPoints: controlPoints,
            degree: degree,
            shouldCloseSamples: shouldCloseSamples,
            hasWrappedControlPoints: hasWrappedControlPoints,
            isPeriodic: isPeriodic
        )
        let sampleControlPoints = usesPeriodicClosure
            ? controlPoints + Array(controlPoints.prefix(degree))
            : controlPoints
        let sampleKnots = usesPeriodicClosure
            ? periodicKnots(from: knots, extraCount: degree)
            : knots
        let sampleWeights = usesPeriodicClosure
            ? periodicWeights(from: weights, extraCount: degree)
            : weights

        let endIndex = usesPeriodicClosure ? controlPoints.count + degree : controlPoints.count
        guard sampleKnots.indices.contains(degree),
              sampleKnots.indices.contains(endIndex) else {
            return shouldCloseSamples ? closedPointSequence(controlPoints) : controlPoints
        }

        let start = sampleKnots[degree]
        let end = sampleKnots[endIndex]
        guard end > start else {
            return shouldCloseSamples ? closedPointSequence(controlPoints) : controlPoints
        }

        let steps = max(24, min(384, sampleControlPoints.count * 18))
        var points: [SIMD2<Float>] = []

        let sampleCount = shouldCloseSamples ? steps : steps + 1
        for step in 0..<sampleCount {
            let t = start + (end - start) * Double(step) / Double(steps)
            let sampleT = !shouldCloseSamples && step == steps ? end.nextDown : t
            var numerator = SIMD2<Double>(0, 0)
            var denominator = 0.0

            for index in sampleControlPoints.indices {
                let basisValue = splineBasis(index: index, degree: degree, t: sampleT, knots: sampleKnots)
                let weight = sampleWeights.indices.contains(index) ? sampleWeights[index] : 1.0
                numerator += SIMD2(Double(sampleControlPoints[index].x), Double(sampleControlPoints[index].y)) * basisValue * weight
                denominator += basisValue * weight
            }

            if abs(denominator) > 0.0000001 {
                points.append(SIMD2(Float(numerator.x / denominator), Float(numerator.y / denominator)))
            }
        }

        if shouldCloseSamples, let firstPoint = points.first {
            points.append(firstPoint)
        }
        return points
    }

    private static func closedPointSequence(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard let first = points.first,
              let last = points.last,
              simd_distance(first, last) > pointClosureTolerance(for: points) else {
            return points
        }
        return points + [first]
    }

    private static func repeatedControlPointPrefixCount(
        in controlPoints: [SIMD2<Float>],
        degree: Int
    ) -> Int {
        guard degree > 0, controlPoints.count > degree else { return 0 }

        let tolerance = pointClosureTolerance(for: controlPoints)
        let maxCount = min(degree, controlPoints.count / 2)
        var wrappedCount = 0

        for count in 1...maxCount {
            var matches = true
            for offset in 0..<count {
                let prefixPoint = controlPoints[offset]
                let suffixPoint = controlPoints[controlPoints.count - count + offset]
                if simd_distance(prefixPoint, suffixPoint) > tolerance {
                    matches = false
                    break
                }
            }

            if matches {
                wrappedCount = count
            }
        }

        return wrappedCount
    }

    private static func isClampedKnotVector(_ knots: [Double], degree: Int) -> Bool {
        guard degree >= 0, knots.count >= (degree + 1) * 2 else { return false }
        return knotMultiplicity(atStartOf: knots) >= degree + 1
            && knotMultiplicity(atEndOf: knots) >= degree + 1
    }

    private static func knotMultiplicity(atStartOf knots: [Double]) -> Int {
        guard let first = knots.first else { return 0 }
        return knots.prefix { abs($0 - first) <= 0.0000001 }.count
    }

    private static func knotMultiplicity(atEndOf knots: [Double]) -> Int {
        guard let last = knots.last else { return 0 }
        return knots.reversed().prefix { abs($0 - last) <= 0.0000001 }.count
    }

    private static func shouldAddPeriodicSplineControlPoints(
        controlPoints: [SIMD2<Float>],
        degree: Int,
        shouldCloseSamples: Bool,
        hasWrappedControlPoints: Bool,
        isPeriodic: Bool
    ) -> Bool {
        guard shouldCloseSamples,
              !hasWrappedControlPoints,
              degree > 1,
              controlPoints.count > degree else {
            return false
        }
        if isPeriodic {
            return true
        }

        guard let first = controlPoints.first,
              let last = controlPoints.last else {
            return false
        }
        return simd_distance(first, last) > pointClosureTolerance(for: controlPoints)
    }

    private static func pointClosureTolerance(for points: [SIMD2<Float>]) -> Float {
        guard var minPoint = points.first,
              var maxPoint = points.first else {
            return 0.0001
        }

        for point in points.dropFirst() {
            minPoint = SIMD2(min(minPoint.x, point.x), min(minPoint.y, point.y))
            maxPoint = SIMD2(max(maxPoint.x, point.x), max(maxPoint.y, point.y))
        }

        let span = max(maxPoint.x - minPoint.x, maxPoint.y - minPoint.y)
        return max(span * 0.00001, 0.0001)
    }

    private static func isClosedPointSequence(_ points: [SIMD2<Float>]) -> Bool {
        guard let first = points.first,
              let last = points.last,
              points.count > 2 else {
            return false
        }
        return simd_distance(first, last) <= pointClosureTolerance(for: points)
    }

    private static func periodicWeights(from weights: [Double], extraCount: Int) -> [Double] {
        guard !weights.isEmpty, extraCount > 0 else { return weights }
        return weights + (0..<extraCount).map { index in
            weights.indices.contains(index) ? weights[index] : 1.0
        }
    }

    private static func periodicKnots(from knots: [Double], extraCount: Int) -> [Double] {
        guard extraCount > 0 else { return knots }

        let positiveSpans = zip(knots, knots.dropFirst())
            .map { $0.1 - $0.0 }
            .filter { $0 > 0.0000001 }
        let fallbackSpan = positiveSpans.last ?? 1.0
        var extended = knots

        for offset in 0..<extraCount {
            let sourceIndex = knots.count - extraCount + offset
            let span: Double
            if sourceIndex > 0, knots.indices.contains(sourceIndex) {
                let candidate = knots[sourceIndex] - knots[sourceIndex - 1]
                span = candidate > 0.0000001 ? candidate : fallbackSpan
            } else {
                span = fallbackSpan
            }
            extended.append((extended.last ?? 0) + span)
        }

        return extended
    }

    private static func splineBasis(index: Int, degree: Int, t: Double, knots: [Double]) -> Double {
        if degree == 0 {
            return knots[index] <= t && t < knots[index + 1] ? 1.0 : 0.0
        }

        var value = 0.0
        let leftDenominator = knots[index + degree] - knots[index]
        if leftDenominator != 0 {
            value += (t - knots[index]) / leftDenominator
                * splineBasis(index: index, degree: degree - 1, t: t, knots: knots)
        }

        let rightDenominator = knots[index + degree + 1] - knots[index + 1]
        if rightDenominator != 0 {
            value += (knots[index + degree + 1] - t) / rightDenominator
                * splineBasis(index: index + 1, degree: degree - 1, t: t, knots: knots)
        }

        return value
    }

    private static func transformed(
        primitive: DXFPrimitive,
        using transform: DXFInsertTransform,
        insertLayerName: String,
        insertColorIndex: Int?,
        insertTrueColor: SIMD4<Float>?
    ) -> DXFPrimitive {
        let layerName = primitive.layerName == "0" ? insertLayerName : primitive.layerName
        let colorIndex = primitive.colorIndex ?? insertColorIndex
        let trueColor = primitive.trueColor ?? insertTrueColor

        let kind: DXFPrimitiveKind
        switch primitive.kind {
        case let .point(center):
            kind = .point(center: transform.apply(center))

        case let .line(start, end):
            kind = .line(start: transform.apply(start), end: transform.apply(end))

        case let .polyline(points, isClosed):
            kind = .polyline(points: points.map(transform.apply), isClosed: isClosed)

        case let .curve(curve):
            kind = .curve(DXFCurve(
                points: curve.points.map(transform.apply),
                isClosed: curve.isClosed,
                anchors: curve.anchors.map {
                    DXFCurveAnchor(point: transform.apply($0.point), role: $0.role)
                }
            ))

        case let .hatchFill(boundaryLoops):
            kind = .hatchFill(boundaryLoops: boundaryLoops.map { $0.map(transform.apply) })

        case let .circle(center, radius):
            kind = .curve(DXFCurve(
                points: arcPoints(center: center, radius: radius, startAngle: 0, endAngle: 360).map(transform.apply),
                isClosed: true,
                anchors: [DXFCurveAnchor(point: transform.apply(center), role: .center)]
            ))

        case let .arc(center, radius, startAngle, endAngle):
            let points = arcPoints(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle).map(transform.apply)
            var anchors = [DXFCurveAnchor(point: transform.apply(center), role: .center)]
            if let first = points.first {
                anchors.append(DXFCurveAnchor(point: first, role: .endpoint))
            }
            if let last = points.last {
                anchors.append(DXFCurveAnchor(point: last, role: .endpoint))
            }
            kind = .curve(DXFCurve(points: points, isClosed: false, anchors: anchors))

        case let .text(text):
            kind = .text(DXFText(
                content: text.content,
                insertion: transform.apply(text.insertion),
                height: text.height * transform.averageScale,
                rotation: text.rotation + transform.rotationDegrees,
                widthFactor: text.widthFactor * transform.widthScaleFactor,
                horizontalAnchor: text.horizontalAnchor,
                verticalAnchor: text.verticalAnchor,
                isBold: text.isBold,
                lines: text.lines
            ))
        }

        return DXFPrimitive(
            layerName: layerName,
            colorIndex: colorIndex,
            trueColor: trueColor,
            isSelectable: primitive.isSelectable,
            kind: kind
        )
    }

    private static func arcPoints(
        center: SIMD2<Float>,
        radius: Float,
        startAngle: Float,
        endAngle: Float
    ) -> [SIMD2<Float>] {
        let sweep = normalizedSweep(from: startAngle, to: endAngle)
        let steps = max(12, min(192, Int(ceil(abs(sweep) / 8.0))))

        return (0...steps).map { step in
            let t = Float(step) / Float(steps)
            let angle = startAngle + sweep * t
            let radians = angle * .pi / 180.0
            return SIMD2(center.x + cos(radians) * radius, center.y + sin(radians) * radius)
        }
    }

    private static func normalizedSweep(from startAngle: Float, to endAngle: Float) -> Float {
        var sweep = endAngle - startAngle
        while sweep <= 0 {
            sweep += 360
        }
        return sweep
    }

    private static func point(xCode: Int, yCode: Int, in pairs: [DXFPair]) -> SIMD2<Float>? {
        guard let x = firstFloat(code: xCode, in: pairs),
              let y = firstFloat(code: yCode, in: pairs) else {
            return nil
        }

        return SIMD2(x, y)
    }

    private static func pairedPoints(xCode: Int, yCode: Int, in pairs: [DXFPair]) -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        var pendingX: Float?

        for pair in pairs {
            switch pair.code {
            case xCode:
                pendingX = Float(pair.value) ?? pendingX
            case yCode:
                if let x = pendingX, let y = Float(pair.value) {
                    points.append(SIMD2(x, y))
                    pendingX = nil
                }
            default:
                continue
            }
        }

        return points
    }

    private static func floats(code: Int, in pairs: [DXFPair]) -> [Float] {
        pairs.compactMap { pair in
            pair.code == code ? Float(pair.value) : nil
        }
    }

    private static func appendPoints(_ newPoints: [SIMD2<Float>], to points: inout [SIMD2<Float>]) {
        for point in newPoints where points.last != point {
            points.append(point)
        }
    }

    private static func makeScene(
        layerDefinitions: [DXFLayerDefinition],
        primitives: [DXFPrimitive],
        unit: DXFUnit
    ) -> DXFScene {
        var counts: [String: Int] = [:]
        for primitive in primitives {
            counts[primitive.layerName, default: 0] += 1
        }

        var definitionsByName = Dictionary(uniqueKeysWithValues: layerDefinitions.map { ($0.name, $0) })
        var orderedNames = layerDefinitions.map(\.name)

        for layerName in counts.keys.sorted() where definitionsByName[layerName] == nil {
            orderedNames.append(layerName)
            definitionsByName[layerName] = DXFLayerDefinition(name: layerName, colorIndex: nil, isVisibleByDefault: true)
        }

        if orderedNames.isEmpty, !primitives.isEmpty {
            orderedNames = ["0"]
            definitionsByName["0"] = DXFLayerDefinition(name: "0", colorIndex: nil, isVisibleByDefault: true)
        }

        let layers = orderedNames.map { name in
            let definition = definitionsByName[name] ?? DXFLayerDefinition(name: name, colorIndex: nil, isVisibleByDefault: true)
            return DXFLayer(
                name: name,
                colorIndex: definition.colorIndex,
                isVisibleByDefault: definition.isVisibleByDefault,
                primitiveCount: counts[name, default: 0]
            )
        }

        return DXFScene(layers: layers, primitives: primitives, unit: unit)
    }

    private static func parseCommonEntityValues(_ pairs: [DXFPair]) -> (layerName: String, colorIndex: Int?, trueColor: SIMD4<Float>?) {
        var layerName = "0"
        var colorIndex: Int?
        var trueColor: SIMD4<Float>?

        for pair in pairs {
            switch pair.code {
            case 8 where !pair.value.isEmpty:
                layerName = pair.value
            case 62:
                if let color = Int(pair.value), color > 0, color < 256 {
                    colorIndex = color
                }
            case 420:
                trueColor = dxfTrueColor(pair.value)
            default:
                continue
            }
        }

        return (layerName, colorIndex, trueColor)
    }

    private static func dxfTrueColor(_ value: String) -> SIMD4<Float>? {
        guard let packed = Int(value), packed >= 0 else { return nil }
        let red = Float((packed >> 16) & 0xff) / 255.0
        let green = Float((packed >> 8) & 0xff) / 255.0
        let blue = Float(packed & 0xff) / 255.0
        return SIMD4(red, green, blue, 1.0)
    }

    private static func collectRecord(from pairs: [DXFPair], startingAt index: Int) -> (pairs: [DXFPair], nextIndex: Int) {
        var cursor = index + 1
        while cursor < pairs.count, pairs[cursor].code != 0 {
            cursor += 1
        }
        return (Array(pairs[index..<cursor]), cursor)
    }

    private static func firstValue(code: Int, in pairs: [DXFPair]) -> String? {
        pairs.first { $0.code == code }?.value
    }

    private static func firstFloat(code: Int, in pairs: [DXFPair]) -> Float? {
        firstValue(code: code, in: pairs).flatMap(Float.init)
    }

    private static func textHorizontalAnchor(in pairs: [DXFPair], isMultiline: Bool) -> DXFTextHorizontalAnchor {
        if isMultiline {
            switch Int(firstValue(code: 71, in: pairs) ?? "1") ?? 1 {
            case 2, 5, 8:
                return .center
            case 3, 6, 9:
                return .right
            default:
                return .left
            }
        }

        switch Int(firstValue(code: 72, in: pairs) ?? "0") ?? 0 {
        case 1, 3, 4, 5:
            return .center
        case 2:
            return .right
        default:
            return .left
        }
    }

    private static func textVerticalAnchor(in pairs: [DXFPair], isMultiline: Bool) -> DXFTextVerticalAnchor {
        if isMultiline {
            switch Int(firstValue(code: 71, in: pairs) ?? "1") ?? 1 {
            case 4, 5, 6:
                return .middle
            case 7, 8, 9:
                return .bottom
            default:
                return .top
            }
        }

        switch Int(firstValue(code: 73, in: pairs) ?? "0") ?? 0 {
        case 1:
            return .bottom
        case 2:
            return .middle
        case 3:
            return .top
        default:
            return .baseline
        }
    }
}

private struct DXFPair {
    let code: Int
    let value: String

    func isMarker(_ marker: String) -> Bool {
        code == 0 && value.uppercased() == marker
    }
}

private struct DXFLayerDefinition {
    let name: String
    let colorIndex: Int?
    let isVisibleByDefault: Bool
}

private struct DXFBlockDefinition {
    let name: String
    let basePoint: SIMD2<Float>
    let primitives: [DXFPrimitive]
}

private struct DXFHatchEdgePath {
    let polylines: [[SIMD2<Float>]]
    let loops: [[SIMD2<Float>]]
    let nextIndex: Int
}

private struct DXFHatchPatternLine {
    let angleDegrees: Float
    let base: SIMD2<Float>
    let offset: SIMD2<Float>
    let dashes: [Float]
}

private struct DXFHeaderSettings {
    let extMin: SIMD2<Float>?
    let extMax: SIMD2<Float>?
    let pointDisplaySize: Float?
    let unit: DXFUnit
    let defaultDimensionStyle: DXFDimensionStyle
    let dimensionStyles: [String: DXFDimensionStyle]

    var referenceSpan: Float {
        guard let extMin, let extMax else { return 1000 }
        return max(max(extMax.x - extMin.x, extMax.y - extMin.y), 1)
    }

    var pointMarkerSize: Float {
        if let pointDisplaySize, pointDisplaySize > 0 {
            return pointDisplaySize
        }
        return max(referenceSpan * 0.006, 0.1)
    }

    func withDimensionStyles(_ styles: [String: DXFDimensionStyle]) -> DXFHeaderSettings {
        DXFHeaderSettings(
            extMin: extMin,
            extMax: extMax,
            pointDisplaySize: pointDisplaySize,
            unit: unit,
            defaultDimensionStyle: defaultDimensionStyle,
            dimensionStyles: styles
        )
    }

    func dimensionStyle(named name: String?) -> DXFDimensionStyle {
        if let name, let style = dimensionStyles[name.uppercased()] {
            return style
        }
        return dimensionStyles[defaultDimensionStyle.name.uppercased()] ?? defaultDimensionStyle
    }
}

private struct DXFDimensionStyle {
    let name: String
    let scale: Float?
    let arrowSize: Float?
    let extensionOffset: Float?
    let extensionBeyond: Float?
    let textHeight: Float?
    let textGap: Float?
    let linearFactor: Float?
    let decimalPrecision: Int?
    let toleranceEnabled: Bool?
    let toleranceUpper: Float?
    let toleranceLower: Float?
    let toleranceHeightScale: Float?
    let tolerancePrecision: Int?

    func resolved(referenceSpan: Float) -> DXFResolvedDimensionStyle {
        let base = max(referenceSpan * 0.015, 0.1)
        let scale = max(self.scale ?? 1, 0.0001)
        let decimalPrecision = min(max(decimalPrecision ?? 3, 0), 8)
        return DXFResolvedDimensionStyle(
            arrowSize: resolvedSize(arrowSize, fallback: base * 0.75, scale: scale),
            extensionOffset: resolvedSize(extensionOffset, fallback: base * 0.25, scale: scale),
            extensionBeyond: resolvedSize(extensionBeyond, fallback: base * 0.5, scale: scale),
            textHeight: resolvedSize(textHeight, fallback: base, scale: scale),
            textGap: resolvedSize(textGap, fallback: base * 0.25, scale: scale),
            linearFactor: linearFactor ?? 1,
            decimalPrecision: decimalPrecision,
            toleranceEnabled: toleranceEnabled ?? false,
            toleranceUpper: toleranceUpper ?? 0,
            toleranceLower: toleranceLower ?? 0,
            toleranceHeightScale: min(max(toleranceHeightScale ?? 0.7, 0.25), 1.0),
            tolerancePrecision: min(max(tolerancePrecision ?? decimalPrecision, 0), 8)
        )
    }

    func applyingOverrides(from pairs: [DXFPair]) -> DXFDimensionStyle {
        let overrides = Self.overrideValues(in: pairs)
        guard !overrides.isEmpty else { return self }

        return DXFDimensionStyle(
            name: name,
            scale: overrides.floatValue(for: 40) ?? scale,
            arrowSize: overrides.floatValue(for: 41) ?? arrowSize,
            extensionOffset: overrides.floatValue(for: 42) ?? extensionOffset,
            extensionBeyond: overrides.floatValue(for: 44) ?? extensionBeyond,
            textHeight: overrides.floatValue(for: 140) ?? textHeight,
            textGap: overrides.floatValue(for: 147) ?? textGap,
            linearFactor: overrides.floatValue(for: 144) ?? linearFactor,
            decimalPrecision: overrides.intValue(for: 271) ?? decimalPrecision,
            toleranceEnabled: overrides.intValue(for: 71).map { $0 != 0 } ?? toleranceEnabled,
            toleranceUpper: overrides.floatValue(for: 47) ?? toleranceUpper,
            toleranceLower: overrides.floatValue(for: 48) ?? toleranceLower,
            toleranceHeightScale: overrides.floatValue(for: 146) ?? toleranceHeightScale,
            tolerancePrecision: overrides.intValue(for: 272) ?? tolerancePrecision
        )
    }

    private func resolvedSize(_ value: Float?, fallback: Float, scale: Float) -> Float {
        let size = value.flatMap { $0 > 0 ? $0 : nil } ?? fallback
        return size * scale
    }

    private static func overrideValues(in pairs: [DXFPair]) -> [Int: String] {
        guard let startIndex = pairs.firstIndex(where: { $0.code == 1000 && $0.value.uppercased() == "DSTYLE" }) else {
            return [:]
        }

        var overrides: [Int: String] = [:]
        var index = startIndex + 1
        var isInsideDStyle = false

        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 1002, pair.value == "{" {
                isInsideDStyle = true
                index += 1
                continue
            }
            if pair.code == 1002, pair.value == "}" {
                break
            }

            if isInsideDStyle,
               (pair.code == 1070 || pair.code == 1071),
               let variableCode = Int(pair.value),
               index + 1 < pairs.count {
                let valuePair = pairs[index + 1]
                overrides[variableCode] = valuePair.value
                index += 2
                continue
            }

            index += 1
        }

        return overrides
    }
}

private struct DXFResolvedDimensionStyle {
    let arrowSize: Float
    let extensionOffset: Float
    let extensionBeyond: Float
    let textHeight: Float
    let textGap: Float
    let linearFactor: Float
    let decimalPrecision: Int
    let toleranceEnabled: Bool
    let toleranceUpper: Float
    let toleranceLower: Float
    let toleranceHeightScale: Float
    let tolerancePrecision: Int
}

private struct DXFDimensionLabel {
    let main: String
    let upperTolerance: String?
    let lowerTolerance: String?
}

private extension Dictionary where Key == Int, Value == String {
    func intValue(for key: Int) -> Int? {
        self[key].flatMap(Int.init)
    }

    func floatValue(for key: Int) -> Float? {
        self[key].flatMap(Float.init)
    }
}

private struct DXFPolylineVertex {
    let point: SIMD2<Float>
    var bulge: Float
}

private struct DXFInsertTransform {
    let insertionPoint: SIMD2<Float>
    let basePoint: SIMD2<Float>
    let scale: SIMD2<Float>
    let rotationDegrees: Float

    func apply(_ point: SIMD2<Float>) -> SIMD2<Float> {
        transformedVector(point - basePoint) + insertionPoint
    }

    func transformedVector(_ vector: SIMD2<Float>) -> SIMD2<Float> {
        let radians = rotationDegrees * .pi / 180.0
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        let local = vector * scale

        return SIMD2(
            local.x * cosValue - local.y * sinValue,
            local.x * sinValue + local.y * cosValue
        )
    }

    var averageScale: Float {
        max((abs(scale.x) + abs(scale.y)) * 0.5, 0.0001)
    }

    var widthScaleFactor: Float {
        max(abs(scale.x) / averageScale, 0.0001)
    }

    func withAdditionalInsertionOffset(_ offset: SIMD2<Float>) -> DXFInsertTransform {
        DXFInsertTransform(
            insertionPoint: insertionPoint + transformedVector(offset),
            basePoint: basePoint,
            scale: scale,
            rotationDegrees: rotationDegrees
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
