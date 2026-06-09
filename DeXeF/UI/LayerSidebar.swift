// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct LayerSidebar: View {
    let scene: DXFScene
    let documentName: String
    let palette: DXFRenderPalette
    let showsLayerActions: Bool
    let onShowDocument: () -> Void
    @Binding var visibleLayers: Set<String>

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        List {
            Section {
                Button(action: onShowDocument) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(documentName)
                                .lineLimit(1)
                            Text("Document")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section {
                ForEach(scene.layers) { layer in
                    Toggle(isOn: binding(for: layer)) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(palette.swiftUIColor(for: layer.colorIndex))
                                .frame(width: 10, height: 10)
                                .overlay {
                                    Circle()
                                        .stroke(.secondary.opacity(0.35), lineWidth: 0.5)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(layer.name)
                                    .lineLimit(1)
                                Text("\(layer.primitiveCount) \(layer.primitiveCount == 1 ? "entity" : "entities")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(navigationTitleText)
        .scrollContentBackground(.hidden)
        .fullBleedDocumentChrome()
        .toolbar {
            if showsLayerActions {
                ToolbarItemGroup {
                    Button {
                        visibleLayers = Set(scene.layers.map(\.name))
                    } label: {
                        Label("Show All", systemImage: "eye")
                    }

                    Button {
                        visibleLayers.removeAll()
                    } label: {
                        Label("Hide All", systemImage: "eye.slash")
                    }
                }
            }
        }
    }

    // On iPhone (compact) the sidebar is its own screen, so it carries the
    // document name as its title. On iPad/macOS it sits beside the drawing and
    // stays labelled "Layers".
    private var navigationTitleText: String {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            return documentName
        }
        #endif
        return "Layers"
    }

    private func binding(for layer: DXFLayer) -> Binding<Bool> {
        Binding {
            visibleLayers.contains(layer.name)
        } set: { isVisible in
            if isVisible {
                visibleLayers.insert(layer.name)
            } else {
                visibleLayers.remove(layer.name)
            }
        }
    }
}
