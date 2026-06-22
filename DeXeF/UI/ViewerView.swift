// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import simd
#if os(macOS)
import AppKit
#endif

struct ViewerView: View {
    let document: DXFDocument

    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @AppStorage(PreferenceKeys.lineThickness) private var lineThickness = DXFRenderStyle.defaultLineThickness
    @AppStorage(PreferenceKeys.lightPalette) private var lightPaletteRawValue = PalettePreset.studio.rawValue
    @AppStorage(PreferenceKeys.darkPalette) private var darkPaletteRawValue = PalettePreset.studio.rawValue
    @AppStorage(PreferenceKeys.lightPaletteColors) private var lightPaletteColors = ""
    @AppStorage(PreferenceKeys.darkPaletteColors) private var darkPaletteColors = ""
    @AppStorage(PreferenceKeys.coordinateDisplayUnit) private var coordinateDisplayUnitRawValue = CoordinateDisplayUnit.drawing.rawValue
    @AppStorage(PreferenceKeys.showsHUD) private var showsHUD = true
    @AppStorage(PreferenceKeys.showsGridMarks) private var showsGridMarks = true
    @AppStorage(PreferenceKeys.selectsCurveSegments) private var selectsCurveSegments = false
    @AppStorage(PreferenceKeys.textFontName) private var textFontName = DXFRenderStyle.defaultTextFontName
    @SceneStorage("viewer.sidebar.visibility") private var sidebarVisibilityRawValue = NavigationSplitViewVisibility.detailOnly.storageValue
    @SceneStorage("viewer.viewport.saved") private var hasSavedViewport = false
    @SceneStorage("viewer.viewport.zoom") private var storedZoom = 1.0
    @SceneStorage("viewer.viewport.panX") private var storedPanX = 0.0
    @SceneStorage("viewer.viewport.panY") private var storedPanY = 0.0

    @State private var visibleLayers: Set<String>
    @State private var isShowingPreferences = false
    @State private var pointerLocation: CGPoint?
    @State private var selectedVertices: [SIMD2<Float>] = []
    @State private var selectedEdge: ViewerSelectedEdge?
    @State private var selectedCurve: ViewerSelectedCurve?
    @State private var sidebarWidth: CGFloat = 260
    @State private var toolbarTopInset: CGFloat = 0
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    @State private var interactionGeometry: ViewerInteractionGeometry?
    @StateObject private var viewport = ViewportController()

    init(document: DXFDocument) {
        self.document = document
        let initialVisibleLayers = Set(document.scene.layers.filter(\.isVisibleByDefault).map(\.name))
        _visibleLayers = State(initialValue: initialVisibleLayers)
        _interactionGeometry = State(initialValue: ViewerInteractionGeometry(scene: document.scene, visibleLayers: initialVisibleLayers, textFontName: DXFRenderStyle.defaultTextFontName, selectsCurveSegments: false))
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: sidebarVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            LayerSidebar(
                scene: document.scene,
                documentName: document.displayName,
                palette: renderStyle.palette,
                showsLayerActions: isSidebarOpen,
                onShowDocument: showDocumentColumn,
                visibleLayers: $visibleLayers
            )
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SidebarWidthPreferenceKey.self, value: proxy.size.width)
                    }
                }
        } detail: {
            documentSurface
        }
        .fullBleedDocumentChrome()
        .onAppear {
            syncPreferredCompactColumn()
        }
        .focusedSceneValue(\.defaultZoomAction, { viewport.reset() })
        .focusedSceneValue(\.clearSelectionAction, { clearSelection() })
        .focusedSceneValue(\.showsHUD, $showsHUD)
        .background(ToolbarTopInsetReporter { topInset in
            if abs(toolbarTopInset - topInset) > 0.5 {
                toolbarTopInset = topInset
            }
        })
        #if os(macOS)
        .background(WindowChromeConfigurator())
        #endif
        .sheet(isPresented: $isShowingPreferences) {
            NavigationStack {
                PreferencesView()
            }
        }
        .task(id: document.id) {
            visibleLayers = Set(document.scene.layers.filter(\.isVisibleByDefault).map(\.name))
            pointerLocation = nil
            selectedVertices = []
            selectedEdge = nil
            selectedCurve = nil
            restoreViewport()
            interactionGeometry = ViewerInteractionGeometry(scene: document.scene, visibleLayers: visibleLayers, textFontName: textFontName, selectsCurveSegments: selectsCurveSegments)
        }
        .onChange(of: visibleLayers) { _, _ in
            pointerLocation = nil
            selectedVertices = []
            selectedEdge = nil
            selectedCurve = nil
            interactionGeometry = ViewerInteractionGeometry(scene: document.scene, visibleLayers: visibleLayers, textFontName: textFontName, selectsCurveSegments: selectsCurveSegments)
        }
        .onChange(of: textFontName) { _, _ in
            pointerLocation = nil
            clearSelection()
            interactionGeometry = ViewerInteractionGeometry(scene: document.scene, visibleLayers: visibleLayers, textFontName: textFontName, selectsCurveSegments: selectsCurveSegments)
        }
        .onChange(of: selectsCurveSegments) { _, _ in
            pointerLocation = nil
            clearSelection()
            interactionGeometry = ViewerInteractionGeometry(scene: document.scene, visibleLayers: visibleLayers, textFontName: textFontName, selectsCurveSegments: selectsCurveSegments)
        }
        .onChange(of: sidebarVisibilityRawValue) { _, _ in
            syncPreferredCompactColumn()
        }
        .onChange(of: viewport.zoom) { _, newValue in
            storedZoom = Double(newValue)
            hasSavedViewport = true
        }
        .onChange(of: viewport.pan) { _, newValue in
            storedPanX = Double(newValue.x)
            storedPanY = Double(newValue.y)
            hasSavedViewport = true
        }
        .onPreferenceChange(SidebarWidthPreferenceKey.self) { width in
            if width > 0 {
                sidebarWidth = width
            }
        }
    }

    private var documentSurface: some View {
        ZStack(alignment: .bottomLeading) {
            MetalCanvas(
                scene: document.scene,
                visibleLayers: visibleLayers,
                renderStyle: renderStyle,
                selectionState: metalSelectionState,
                viewport: viewport,
                minimumContentInsets: viewportMinimumContentInsets,
                onPointerMoved: { location, _, _ in
                    pointerLocation = location
                },
                onPointerEnded: {
                    pointerLocation = nil
                },
                onSelectAt: selectGeometry
            )
                .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])

            ViewerInteractionOverlay(
                renderStyle: renderStyle,
                viewport: viewport,
                interactionGeometry: interactionGeometry,
                pointerLocation: pointerLocation,
                showsHUD: showsHUD,
                declaredUnit: document.scene.unit,
                displayUnit: CoordinateDisplayUnit.stored(coordinateDisplayUnitRawValue),
                minimumContentInsets: viewportMinimumContentInsets,
                selectedVertices: selectedVertices,
                selectedEdge: selectedEdge,
                selectedCurve: selectedCurve
            )
            .allowsHitTesting(false)

            if document.scene.primitives.isEmpty {
                ContentUnavailableView("No Drawable Geometry", systemImage: "doc.text.magnifyingglass")
            }
        }
        .background {
            renderStyle.palette.background.swiftUIColor
                .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])
        }
        .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])
        .navigationTitle(detailNavigationTitle)
        #if !os(macOS)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isShowingPreferences = true
                } label: {
                    Label("Preferences", systemImage: "gearshape")
                }
            }
        }
        #endif
    }

    private func selectGeometry(at location: CGPoint, in size: CGSize, contentInsets: ViewportInsets) {
        guard let snapshot = interactionSnapshot(size: size, contentInsets: contentInsets) else {
            clearSelection()
            return
        }

        if let snap = snapshot.snappedVertex(near: location) {
            selectedEdge = nil
            selectedCurve = nil

            if let existingIndex = selectedVertices.firstIndex(where: { simd_distance($0, snap.point) <= snapshot.modelTolerance }) {
                selectedVertices.remove(at: existingIndex)
                return
            }

            selectedVertices.append(snap.point)
            if selectedVertices.count > 2 {
                selectedVertices.removeFirst(selectedVertices.count - 2)
            }
            return
        }

        if let curveSnap = snapshot.snappedCurve(near: location) {
            selectedVertices.removeAll()
            selectedEdge = nil
            if selectedCurve?.id == curveSnap.curve.id {
                selectedCurve = nil
            } else {
                selectedCurve = curveSnap.curve
            }
            return
        }

        if let edgeSnap = snapshot.snappedEdge(near: location) {
            selectedVertices.removeAll()
            selectedCurve = nil
            if selectedEdge?.id == edgeSnap.edge.id {
                selectedEdge = nil
            } else {
                selectedEdge = edgeSnap.edge
            }
            return
        }

        clearSelection()
    }

    private func clearSelection() {
        selectedVertices.removeAll()
        selectedEdge = nil
        selectedCurve = nil
    }

    // Restore the persisted zoom/pan on (re)appearance — including scene state
    // restoration — falling back to a fitted reset when nothing is stored yet.
    private func restoreViewport() {
        if hasSavedViewport {
            viewport.restore(zoom: Float(storedZoom), pan: SIMD2(Float(storedPanX), Float(storedPanY)))
        } else {
            viewport.reset()
        }
    }

    private func showDocumentColumn() {
        preferredCompactColumn = .detail
    }

    private func syncPreferredCompactColumn() {
        preferredCompactColumn = isSidebarOpen ? .sidebar : .detail
    }

    private func interactionSnapshot(size: CGSize, contentInsets: ViewportInsets) -> ViewerInteractionSnapshot? {
        guard let interactionGeometry else { return nil }

        return ViewerInteractionSnapshot(
            geometry: interactionGeometry,
            viewport: viewport,
            size: size,
            contentInsets: contentInsets
        )
    }

    private var renderStyle: DXFRenderStyle {
        let mode = RenderColorMode(colorScheme)
        let preset = mode == .dark
            ? PalettePreset.stored(darkPaletteRawValue)
            : PalettePreset.stored(lightPaletteRawValue)
        let storedColors = mode == .dark ? darkPaletteColors : lightPaletteColors

        return DXFRenderStyle(
            palette: preset.palette(for: mode).applyingStoredColors(storedColors),
            lineThickness: Float(lineThickness),
            showsGridMarks: showsGridMarks,
            textFontName: textFontName
        )
    }

    private var metalSelectionState: MetalSelectionState {
        MetalSelectionState(
            vertices: selectedVertices,
            edge: selectedEdge.map { MetalSelectionEdge(start: $0.start, end: $0.end) },
            curve: selectedCurve.map { curve in
                MetalSelectionCurve(
                    points: curve.points,
                    isClosed: curve.isClosed,
                    anchors: curve.anchors.map {
                        MetalSelectionAnchor(point: $0.point, role: MetalSelectionAnchorRole($0.role))
                    }
                )
            }
        )
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            NavigationSplitViewVisibility(storageValue: sidebarVisibilityRawValue)
        } set: { newValue in
            sidebarVisibilityRawValue = newValue.storageValue
        }
    }

    private var isSidebarOpen: Bool {
        isSidebarOpen(NavigationSplitViewVisibility(storageValue: sidebarVisibilityRawValue))
    }

    private func isSidebarOpen(_ visibility: NavigationSplitViewVisibility) -> Bool {
        switch visibility {
        case .all, .doubleColumn:
            return true
        case .automatic:
            return true
        default:
            return false
        }
    }

    private var viewportMinimumContentInsets: ViewportInsets {
        ViewportInsets(
            top: Float(toolbarTopInset),
            leading: shouldReserveSidebarInset ? Float(sidebarWidth) : 0,
            bottom: 0,
            trailing: 0
        )
    }

    private var shouldReserveSidebarInset: Bool {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            return false
        }
        #endif

        return isSidebarOpen
    }

    // On iPhone (compact) the layer sidebar and the drawing are separate
    // stacked screens; the document name titles the sidebar instead, so the
    // graphical view shows no title. On iPad/macOS the two columns are visible
    // together and the detail keeps the document name.
    private var detailNavigationTitle: String {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            return ""
        }
        #endif
        return document.displayName
    }
}

private struct SidebarWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ViewerInteractionOverlay: View {
    let renderStyle: DXFRenderStyle
    @ObservedObject var viewport: ViewportController
    let interactionGeometry: ViewerInteractionGeometry?
    let pointerLocation: CGPoint?
    let showsHUD: Bool
    let declaredUnit: DXFUnit
    let displayUnit: CoordinateDisplayUnit
    let minimumContentInsets: ViewportInsets
    let selectedVertices: [SIMD2<Float>]
    let selectedEdge: ViewerSelectedEdge?
    let selectedCurve: ViewerSelectedCurve?

    var body: some View {
        GeometryReader { proxy in
            let contentInsets = ViewportInsets(proxy.safeAreaInsets).merged(withMinimum: minimumContentInsets)
            let snapshot = interactionGeometry.flatMap {
                ViewerInteractionSnapshot(
                    geometry: $0,
                    viewport: viewport,
                    size: proxy.size,
                    contentInsets: contentInsets
                )
            }

            ZStack(alignment: .bottomTrailing) {
                if let snapshot {
                    snapMarker(snapshot: snapshot)
                }

                if showsHUD {
                    CoordinateReadout(
                        pointerState: snapshot.flatMap { snapshot in
                            pointerLocation.map { snapshot.pointerState(at: $0) }
                        },
                        gridSpacing: renderStyle.showsGridMarks ? snapshot?.gridSpacing : nil,
                        declaredUnit: declaredUnit,
                        displayUnit: displayUnit,
                        selectedVertices: selectedVertices,
                        selectedEdge: selectedEdge,
                        selectedCurve: selectedCurve
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomTrailing)
        }
    }

    @ViewBuilder
    private func snapMarker(snapshot: ViewerInteractionSnapshot) -> some View {
        if let pointerLocation {
            let pointerState = snapshot.pointerState(at: pointerLocation)
            if pointerState.snap != nil {
                CursorSnapMarker()
                    .position(pointerState.screenPoint)
            }
        }
    }
}

private struct CoordinateReadout: View {
    let pointerState: ViewerPointerState?
    let gridSpacing: Float?
    let declaredUnit: DXFUnit
    let displayUnit: CoordinateDisplayUnit
    let selectedVertices: [SIMD2<Float>]
    let selectedEdge: ViewerSelectedEdge?
    let selectedCurve: ViewerSelectedCurve?

    private let coordinateLabelWidth: CGFloat = 18
    private let coordinateValueWidth: CGFloat = 92
    private let cornerRadius: CGFloat = 8

    var body: some View {
        let coordinate = formattedCoordinate

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let distance = distanceMeasurement {
                readout(label: "Distance:", value: distance)
            }

            if let gridSpacing {
                readout(label: "Grid:", value: formatMeasurement(gridSpacing))
            }

            coordinateReadout(label: "X:", value: coordinate.x)
            coordinateReadout(label: "Y:", value: coordinate.y)

            if let unit = coordinate.unit {
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .font(.system(.caption, design: .monospaced))
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(0.08))
                .blendMode(.overlay)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
    }

    private var formattedCoordinate: (x: String, y: String, unit: String?) {
        let unit = displayUnit.displayAbbreviation(from: declaredUnit)
        guard let point = pointerState?.displayPoint else {
            return ("--", "--", unit)
        }

        let x = displayUnit.displayValue(point.x, from: declaredUnit)
        let y = displayUnit.displayValue(point.y, from: declaredUnit)
        return (format(x), format(y), unit)
    }

    private var distanceMeasurement: String? {
        if let selectedEdge {
            return formatMeasurement(selectedEdge.length)
        }
        if let selectedCurve {
            return formatMeasurement(selectedCurve.length)
        }
        guard selectedVertices.count == 2 else { return nil }
        return formatMeasurement(simd_distance(selectedVertices[0], selectedVertices[1]))
    }

    private func readout(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func coordinateReadout(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: coordinateLabelWidth, alignment: .trailing)
            Text(value)
                .foregroundStyle(.primary)
                .frame(width: coordinateValueWidth, alignment: .trailing)
                .minimumScaleFactor(0.8)
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private func format(_ value: Float) -> String {
        format(Double(value))
    }

    private func format(_ value: Double) -> String {
        let absoluteValue = abs(value)
        if absoluteValue == 0 || absoluteValue >= 0.001 {
            return String(format: "%.3f", value)
        }
        return String(format: "%.6g", value)
    }

    private func formatMeasurement(_ value: Float) -> String {
        let displayValue = displayUnit.displayValue(value, from: declaredUnit)
        guard let abbreviation = displayUnit.displayAbbreviation(from: declaredUnit) else { return format(displayValue) }
        return "\(format(displayValue)) \(abbreviation)"
    }
}

private struct CursorSnapMarker: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: 24, height: 1.5)
            Rectangle()
                .fill(color)
                .frame(width: 1.5, height: 24)

            Circle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: 11, height: 11)
        }
        .frame(width: 32, height: 32)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
    }

    private var color: Color {
        .yellow
    }
}

private struct ViewerPointerState {
    let screenPoint: CGPoint
    let displayPoint: SIMD2<Float>
    let snap: ViewerSnap?
}

private struct ViewerSnap {
    let point: SIMD2<Float>
    let screenPoint: CGPoint
    let distance: CGFloat
}

private struct ViewerEdgeSnap {
    let edge: ViewerSelectedEdge
    let screenPoint: CGPoint
    let distance: CGFloat
}

private struct ViewerCurveSnap {
    let curve: ViewerSelectedCurve
    let screenPoint: CGPoint
    let distance: CGFloat
}

private struct ViewerSelectedEdge: Equatable, Identifiable {
    let id: Int
    let start: SIMD2<Float>
    let end: SIMD2<Float>

    var length: Float {
        simd_distance(start, end)
    }
}

private enum ViewerCurveAnchorRole: Equatable {
    case center
    case endpoint
    case controlPoint
    case fitPoint

    init(_ role: DXFCurveAnchorRole) {
        switch role {
        case .center:
            self = .center
        case .endpoint:
            self = .endpoint
        case .controlPoint:
            self = .controlPoint
        case .fitPoint:
            self = .fitPoint
        }
    }
}

private extension MetalSelectionAnchorRole {
    init(_ role: ViewerCurveAnchorRole) {
        switch role {
        case .center:
            self = .center
        case .endpoint:
            self = .endpoint
        case .controlPoint:
            self = .controlPoint
        case .fitPoint:
            self = .fitPoint
        }
    }
}

private struct ViewerCurveAnchor: Equatable, Identifiable {
    let id: Int
    let point: SIMD2<Float>
    let role: ViewerCurveAnchorRole
}

private struct ViewerSelectedCurve: Equatable, Identifiable {
    let id: Int
    let points: [SIMD2<Float>]
    let isClosed: Bool
    let anchors: [ViewerCurveAnchor]

    var length: Float {
        guard points.count >= 2 else { return 0 }
        var total: Float = 0
        for index in 0..<(points.count - 1) {
            total += simd_distance(points[index], points[index + 1])
        }
        if isClosed,
           let first = points.first,
           let last = points.last,
           simd_distance(first, last) > 0.00001 {
            total += simd_distance(last, first)
        }
        return total
    }
}

private struct ViewerCurve {
    let id: Int
    let points: [SIMD2<Float>]
    let isClosed: Bool
    let anchors: [ViewerCurveAnchor]
    let minX: Float
    let maxX: Float
    let minY: Float
    let maxY: Float

    init?(id: Int, points: [SIMD2<Float>], isClosed: Bool, anchors: [ViewerCurveAnchor]) {
        guard points.count >= 2,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }

        self.id = id
        self.points = points
        self.isClosed = isClosed
        self.anchors = anchors
        minX = points.map(\.x).min() ?? 0
        maxX = points.map(\.x).max() ?? 0
        minY = points.map(\.y).min() ?? 0
        maxY = points.map(\.y).max() ?? 0
    }

    var selectedCurve: ViewerSelectedCurve {
        ViewerSelectedCurve(id: id, points: points, isClosed: isClosed, anchors: anchors)
    }
}

private struct ViewerEdge {
    let id: Int
    let start: SIMD2<Float>
    let end: SIMD2<Float>
    let minX: Float
    let maxX: Float
    let minY: Float
    let maxY: Float
    let length: Float

    init?(id: Int, segment: RenderSegment) {
        let length = simd_distance(segment.start, segment.end)
        guard length.isFinite, length > 0 else { return nil }

        self.id = id
        start = segment.start
        end = segment.end
        minX = min(segment.start.x, segment.end.x)
        maxX = max(segment.start.x, segment.end.x)
        minY = min(segment.start.y, segment.end.y)
        maxY = max(segment.start.y, segment.end.y)
        self.length = length
    }

    var selectedEdge: ViewerSelectedEdge {
        ViewerSelectedEdge(id: id, start: start, end: end)
    }
}

private struct ViewerInteractionGeometry {
    let bounds: DXFBounds
    let vertices: [SIMD2<Float>]
    let verticesByX: [SIMD2<Float>]
    let edgesByMinX: [ViewerEdge]
    let curves: [ViewerCurve]

    init?(scene: DXFScene, visibleLayers: Set<String>, textFontName: String, selectsCurveSegments: Bool) {
        let geometry = GeometryBuilder.build(
            scene: scene,
            visibleLayers: visibleLayers,
            palette: .standardDark,
            includeTextFills: false,
            textFontName: textFontName
        )
        guard let bounds = geometry.bounds else { return nil }

        let curves = Self.curves(in: scene, visibleLayers: visibleLayers)
        let selectableSegments = geometry.segments.filter {
            $0.isSelectable && (selectsCurveSegments || !$0.isCurveApproximation)
        }
        let selectablePoints = geometry.points.filter(\.isSelectable).map(\.center)
        let curveAnchors = curves.flatMap { $0.anchors.map(\.point) }
        let vertices = Self.uniqueVertices(from: selectableSegments, points: selectablePoints + curveAnchors)
        self.bounds = bounds
        self.vertices = vertices
        self.curves = curves
        verticesByX = vertices.sorted {
            if $0.x == $1.x {
                return $0.y < $1.y
            }
            return $0.x < $1.x
        }
        edgesByMinX = selectableSegments.enumerated().compactMap { index, segment in
            ViewerEdge(id: index, segment: segment)
        }
        .sorted {
            if $0.minX == $1.minX {
                return $0.minY < $1.minY
            }
            return $0.minX < $1.minX
        }
    }

    func xRange(near point: SIMD2<Float>, tolerance: Float) -> Range<Int> {
        lowerBound(forX: point.x - tolerance)..<lowerBound(forX: point.x + tolerance)
    }

    func edgeRange(near point: SIMD2<Float>, tolerance: Float) -> Range<Int> {
        edgesByMinX.startIndex..<upperBoundForEdgeMinX(point.x + tolerance)
    }

    private func lowerBound(forX value: Float) -> Int {
        var low = verticesByX.startIndex
        var high = verticesByX.endIndex

        while low < high {
            let middle = low + (high - low) / 2
            if verticesByX[middle].x < value {
                low = middle + 1
            } else {
                high = middle
            }
        }

        return low
    }

    private func upperBoundForEdgeMinX(_ value: Float) -> Int {
        var low = edgesByMinX.startIndex
        var high = edgesByMinX.endIndex

        while low < high {
            let middle = low + (high - low) / 2
            if edgesByMinX[middle].minX <= value {
                low = middle + 1
            } else {
                high = middle
            }
        }

        return low
    }

    private static func uniqueVertices(from segments: [RenderSegment], points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var seen: Set<VertexKey> = []
        var vertices: [SIMD2<Float>] = []

        for point in points {
            append(point, seen: &seen, vertices: &vertices)
        }

        for segment in segments {
            append(segment.start, seen: &seen, vertices: &vertices)
            append(segment.end, seen: &seen, vertices: &vertices)
        }

        return vertices
    }

    private static func curves(in scene: DXFScene, visibleLayers: Set<String>) -> [ViewerCurve] {
        scene.primitives.enumerated().compactMap { index, primitive in
            guard primitive.isSelectable,
                  visibleLayers.contains(primitive.layerName) else {
                return nil
            }

            switch primitive.kind {
            case let .circle(center, radius):
                guard radius > 0 else { return nil }
                let points = arcPoints(center: center, radius: radius, startAngle: 0, endAngle: 360)
                let anchors = [ViewerCurveAnchor(id: 0, point: center, role: .center)]
                return ViewerCurve(id: index, points: points, isClosed: true, anchors: anchors)

            case let .arc(center, radius, startAngle, endAngle):
                guard radius > 0 else { return nil }
                let points = arcPoints(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
                var anchors = [ViewerCurveAnchor(id: 0, point: center, role: .center)]
                if let first = points.first {
                    anchors.append(ViewerCurveAnchor(id: 1, point: first, role: .endpoint))
                }
                if let last = points.last {
                    anchors.append(ViewerCurveAnchor(id: 2, point: last, role: .endpoint))
                }
                return ViewerCurve(id: index, points: points, isClosed: false, anchors: anchors)

            case let .curve(curve):
                let anchors = uniqueCurveAnchors(curve.anchors)
                return ViewerCurve(id: index, points: curve.points, isClosed: curve.isClosed, anchors: anchors)

            default:
                return nil
            }
        }
    }

    private static func uniqueCurveAnchors(_ anchors: [DXFCurveAnchor]) -> [ViewerCurveAnchor] {
        var seen: Set<VertexKey> = []
        var result: [ViewerCurveAnchor] = []

        for anchor in anchors {
            let key = VertexKey(anchor.point)
            if seen.insert(key).inserted {
                result.append(ViewerCurveAnchor(id: result.count, point: anchor.point, role: ViewerCurveAnchorRole(anchor.role)))
            }
        }

        return result
    }

    private static func arcPoints(
        center: SIMD2<Float>,
        radius: Float,
        startAngle: Float,
        endAngle: Float
    ) -> [SIMD2<Float>] {
        let sweep = normalizedSweep(from: startAngle, to: endAngle)
        let segmentCount = max(12, min(192, Int(ceil(abs(sweep) / 8.0))))
        return (0...segmentCount).map { step in
            let t = Float(step) / Float(segmentCount)
            let angle = (startAngle + sweep * t) * .pi / 180
            return SIMD2(center.x + cos(angle) * radius, center.y + sin(angle) * radius)
        }
    }

    private static func normalizedSweep(from startAngle: Float, to endAngle: Float) -> Float {
        var sweep = endAngle - startAngle
        while sweep <= 0 {
            sweep += 360
        }
        return sweep
    }

    private static func append(_ point: SIMD2<Float>, seen: inout Set<VertexKey>, vertices: inout [SIMD2<Float>]) {
        let key = VertexKey(point)
        if seen.insert(key).inserted {
            vertices.append(point)
        }
    }
}

private struct ViewerInteractionSnapshot {
    let geometry: ViewerInteractionGeometry
    let bounds: DXFBounds
    let size: CGSize
    let pan: SIMD2<Float>
    let fitOffset: SIMD2<Float>
    let scaleX: Float
    let scaleY: Float
    let pixelsPerUnit: Float

    init?(
        geometry: ViewerInteractionGeometry,
        viewport: ViewportController,
        size: CGSize,
        contentInsets: ViewportInsets
    ) {
        guard size.width > 0, size.height > 0 else { return nil }

        let bounds = geometry.bounds

        let width = Float(size.width)
        let height = Float(size.height)
        let leading = min(max(contentInsets.leading, 0), width - 1)
        let trailing = min(max(contentInsets.trailing, 0), width - leading - 1)
        let top = min(max(contentInsets.top, 0), height - 1)
        let bottom = min(max(contentInsets.bottom, 0), height - top - 1)
        let contentWidth = max(width - leading - trailing, 1)
        let contentHeight = max(height - top - bottom, 1)
        let pixelsPerUnit = min(contentWidth / bounds.width, contentHeight / bounds.height) * 0.92 * viewport.zoom

        guard pixelsPerUnit.isFinite, pixelsPerUnit > 0 else { return nil }

        self.geometry = geometry
        self.bounds = bounds
        self.size = size
        self.pan = viewport.pan
        self.pixelsPerUnit = pixelsPerUnit
        self.scaleX = 2.0 * pixelsPerUnit / width
        self.scaleY = 2.0 * pixelsPerUnit / height
        self.fitOffset = SIMD2(
            (leading + contentWidth * 0.5) / width * 2.0 - 1.0,
            1.0 - (top + contentHeight * 0.5) / height * 2.0
        )
    }

    var modelTolerance: Float {
        max(8.0 / pixelsPerUnit, 0.0001)
    }

    var gridSpacing: Float {
        AdaptiveGrid.spacing(forPixelsPerUnit: pixelsPerUnit)
    }

    func pointerState(at location: CGPoint) -> ViewerPointerState {
        if let snap = snappedVertex(near: location) {
            return ViewerPointerState(screenPoint: snap.screenPoint, displayPoint: snap.point, snap: snap)
        }

        return ViewerPointerState(screenPoint: location, displayPoint: worldPoint(for: location), snap: nil)
    }

    func snappedVertex(near location: CGPoint, maxDistance: CGFloat = 12) -> ViewerSnap? {
        var best: ViewerSnap?
        let worldLocation = worldPoint(for: location)
        let modelTolerance = Float(maxDistance) / pixelsPerUnit
        let range = geometry.xRange(near: worldLocation, tolerance: modelTolerance)

        for vertex in geometry.verticesByX[range] where abs(vertex.y - worldLocation.y) <= modelTolerance {
            let screenPoint = screenPoint(for: vertex)
            guard screenPoint.x.isFinite, screenPoint.y.isFinite else { continue }

            let distance = hypot(screenPoint.x - location.x, screenPoint.y - location.y)
            if distance <= maxDistance, best == nil || distance < best!.distance {
                best = ViewerSnap(point: vertex, screenPoint: screenPoint, distance: distance)
            }
        }

        return best
    }

    func snappedEdge(near location: CGPoint, maxDistance: CGFloat = 10) -> ViewerEdgeSnap? {
        var best: ViewerEdgeSnap?
        let worldLocation = worldPoint(for: location)
        let modelTolerance = Float(maxDistance) / pixelsPerUnit
        let range = geometry.edgeRange(near: worldLocation, tolerance: modelTolerance)

        for edge in geometry.edgesByMinX[range] {
            guard edge.maxX >= worldLocation.x - modelTolerance,
                  edge.minY <= worldLocation.y + modelTolerance,
                  edge.maxY >= worldLocation.y - modelTolerance else {
                continue
            }

            let closestWorldPoint = closestPoint(on: edge, to: worldLocation)
            let screenPoint = screenPoint(for: closestWorldPoint)
            guard screenPoint.x.isFinite, screenPoint.y.isFinite else { continue }

            let distance = hypot(screenPoint.x - location.x, screenPoint.y - location.y)
            if distance <= maxDistance, best == nil || distance < best!.distance {
                best = ViewerEdgeSnap(edge: edge.selectedEdge, screenPoint: screenPoint, distance: distance)
            }
        }

        return best
    }

    func snappedCurve(near location: CGPoint, maxDistance: CGFloat = 10) -> ViewerCurveSnap? {
        var best: ViewerCurveSnap?
        let worldLocation = worldPoint(for: location)
        let modelTolerance = Float(maxDistance) / pixelsPerUnit

        for curve in geometry.curves {
            guard curve.maxX >= worldLocation.x - modelTolerance,
                  curve.minX <= worldLocation.x + modelTolerance,
                  curve.maxY >= worldLocation.y - modelTolerance,
                  curve.minY <= worldLocation.y + modelTolerance else {
                continue
            }

            for segment in curveSegments(for: curve) {
                let closestWorldPoint = closestPoint(from: segment.start, to: segment.end, near: worldLocation)
                let screenPoint = screenPoint(for: closestWorldPoint)
                guard screenPoint.x.isFinite, screenPoint.y.isFinite else { continue }

                let distance = hypot(screenPoint.x - location.x, screenPoint.y - location.y)
                if distance <= maxDistance, best == nil || distance < best!.distance {
                    best = ViewerCurveSnap(curve: curve.selectedCurve, screenPoint: screenPoint, distance: distance)
                }
            }
        }

        return best
    }

    func worldPoint(for screenPoint: CGPoint) -> SIMD2<Float> {
        let clip = clipPoint(for: screenPoint)
        let center = bounds.center
        return SIMD2(
            (clip.x - fitOffset.x - pan.x) / scaleX + center.x,
            (clip.y - fitOffset.y - pan.y) / scaleY + center.y
        )
    }

    func screenPoint(for worldPoint: SIMD2<Float>) -> CGPoint {
        let center = bounds.center
        let clipX = (worldPoint.x - center.x) * scaleX + fitOffset.x + pan.x
        let clipY = (worldPoint.y - center.y) * scaleY + fitOffset.y + pan.y

        return CGPoint(
            x: CGFloat((clipX + 1.0) * 0.5) * size.width,
            y: CGFloat((1.0 - clipY) * 0.5) * size.height
        )
    }

    private func clipPoint(for point: CGPoint) -> SIMD2<Float> {
        SIMD2(
            Float(point.x / size.width) * 2.0 - 1.0,
            1.0 - Float(point.y / size.height) * 2.0
        )
    }

    private func closestPoint(on edge: ViewerEdge, to point: SIMD2<Float>) -> SIMD2<Float> {
        closestPoint(from: edge.start, to: edge.end, near: point)
    }

    private func closestPoint(from start: SIMD2<Float>, to end: SIMD2<Float>, near point: SIMD2<Float>) -> SIMD2<Float> {
        let delta = end - start
        let lengthSquared = simd_length_squared(delta)
        guard lengthSquared.isFinite, lengthSquared > 0 else { return start }

        let t = simd_dot(point - start, delta) / lengthSquared
        return start + delta * min(max(t, 0), 1)
    }

    private func curveSegments(for curve: ViewerCurve) -> [(start: SIMD2<Float>, end: SIMD2<Float>)] {
        guard curve.points.count >= 2 else { return [] }

        var segments = (0..<(curve.points.count - 1)).map { index in
            (start: curve.points[index], end: curve.points[index + 1])
        }
        if curve.isClosed,
           let first = curve.points.first,
           let last = curve.points.last,
           simd_distance(first, last) > 0.00001 {
            segments.append((start: last, end: first))
        }
        return segments
    }

}

private struct VertexKey: Hashable {
    let x: Int
    let y: Int

    init(_ point: SIMD2<Float>) {
        x = Int((point.x * 1000).rounded())
        y = Int((point.y * 1000).rounded())
    }
}

extension View {
    @ViewBuilder
    func fullBleedDocumentChrome() -> some View {
        #if os(macOS)
        toolbarBackground(.hidden, for: .windowToolbar)
        #else
        toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }
}

private extension NavigationSplitViewVisibility {
    init(storageValue: String) {
        switch storageValue {
        case "all":
            self = .all
        case "doubleColumn":
            self = .doubleColumn
        case "detailOnly":
            self = .detailOnly
        default:
            self = .automatic
        }
    }

    var storageValue: String {
        switch self {
        case .automatic:
            return "automatic"
        case .all:
            return "all"
        case .doubleColumn:
            return "doubleColumn"
        case .detailOnly:
            return "detailOnly"
        default:
            return "automatic"
        }
    }
}

#if os(macOS)
private struct ToolbarTopInsetReporter: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ToolbarTopInsetReportingView {
        let view = ToolbarTopInsetReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ToolbarTopInsetReportingView, context: Context) {
        view.onChange = onChange
        view.reportSoon()
    }
}

private final class ToolbarTopInsetReportingView: NSView {
    var onChange: ((CGFloat) -> Void)?
    private var lastReportedTopInset: CGFloat = -1
    nonisolated(unsafe) private var resizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }

        if let window {
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                // Delivered on the main queue, so it is safe to assume isolation.
                MainActor.assumeIsolated {
                    self?.reportSoon()
                }
            }
        }

        reportSoon()
    }

    override func layout() {
        super.layout()
        reportSoon()
    }

    deinit {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
    }

    func reportSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.report()
            DispatchQueue.main.async { [weak self] in
                self?.report()
            }
        }
    }

    private func report() {
        let topInset = measuredTopInset()
        guard topInset.isFinite, abs(topInset - lastReportedTopInset) > 0.5 else { return }
        lastReportedTopInset = topInset
        onChange?(topInset)
    }

    private func measuredTopInset() -> CGFloat {
        guard let window, let contentView = window.contentView else {
            return safeAreaInsets.top
        }

        let contentBounds = contentView.bounds
        let contentLayoutRect = window.contentLayoutRect
        var candidates: [CGFloat] = [safeAreaInsets.top]

        appendTopInsetCandidate(from: contentLayoutRect, in: contentBounds, to: &candidates)
        appendTopInsetCandidate(from: contentView.convert(contentLayoutRect, from: nil), in: contentBounds, to: &candidates)

        let frameDifference = window.frame.height - contentLayoutRect.height
        if frameDifference.isFinite {
            candidates.append(frameDifference)
        }

        return candidates
            .filter { $0.isFinite && $0 >= 0 && $0 <= 240 }
            .max() ?? 0
    }

    private func appendTopInsetCandidate(from rect: CGRect, in bounds: CGRect, to candidates: inout [CGFloat]) {
        let topInset = bounds.maxY - rect.maxY
        if topInset.isFinite {
            candidates.append(topInset)
        }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: view.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("DeXeFDocumentWindow")
        window.isRestorable = true
    }
}
#else
private struct ToolbarTopInsetReporter: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ToolbarTopInsetReportingView {
        let view = ToolbarTopInsetReportingView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ToolbarTopInsetReportingView, context: Context) {
        view.onChange = onChange
        view.reportSoon()
    }
}

private final class ToolbarTopInsetReportingView: UIView {
    var onChange: ((CGFloat) -> Void)?
    private var lastReportedTopInset: CGFloat = -1

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportSoon()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        reportSoon()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportSoon()
    }

    func reportSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.report()
            DispatchQueue.main.async { [weak self] in
                self?.report()
            }
        }
    }

    private func report() {
        let topInset = measuredTopInset()
        guard topInset.isFinite, abs(topInset - lastReportedTopInset) > 0.5 else { return }
        lastReportedTopInset = topInset
        onChange?(topInset)
    }

    private func measuredTopInset() -> CGFloat {
        var candidates: [CGFloat] = [
            safeAreaInsets.top,
            safeAreaLayoutGuide.layoutFrame.minY
        ]

        if let window {
            candidates.append(window.safeAreaInsets.top)
            appendTopBarCandidates(in: window, to: &candidates)
        }

        return candidates
            .filter { $0.isFinite && $0 >= 0 && $0 <= 240 }
            .max() ?? 0
    }

    private func appendTopBarCandidates(in view: UIView, to candidates: inout [CGFloat]) {
        guard !view.isHidden, view.alpha > 0.01 else { return }

        if view is UINavigationBar || view is UIToolbar {
            let frame = view.convert(view.bounds, to: self)
            if frame.width > 1,
               frame.height > 1,
               frame.maxY > 0,
               frame.minY < 240,
               frame.maxY.isFinite {
                candidates.append(frame.maxY)
            }
        }

        for subview in view.subviews {
            appendTopBarCandidates(in: subview, to: &candidates)
        }
    }
}
#endif
