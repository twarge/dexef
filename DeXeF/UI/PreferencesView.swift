// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct PreferencesView: View {
    @AppStorage(PreferenceKeys.theme) private var themeRawValue = AppTheme.system.rawValue
    @AppStorage(PreferenceKeys.lineThickness) private var lineThickness = DXFRenderStyle.defaultLineThickness
    @AppStorage(PreferenceKeys.showsHUD) private var showsHUD = true
    @AppStorage(PreferenceKeys.showsGridMarks) private var showsGridMarks = true
    @AppStorage(PreferenceKeys.selectsCurveSegments) private var selectsCurveSegments = false
    @AppStorage(PreferenceKeys.textFontName) private var textFontName = DXFRenderStyle.defaultTextFontName
    @AppStorage(PreferenceKeys.coordinateDisplayUnit) private var coordinateDisplayUnitRawValue = CoordinateDisplayUnit.drawing.rawValue
    @AppStorage(PreferenceKeys.lightPalette) private var lightPaletteRawValue = PalettePreset.studio.rawValue
    @AppStorage(PreferenceKeys.darkPalette) private var darkPaletteRawValue = PalettePreset.studio.rawValue
    @AppStorage(PreferenceKeys.lightPaletteColors) private var lightPaletteColors = ""
    @AppStorage(PreferenceKeys.darkPaletteColors) private var darkPaletteColors = ""

    var body: some View {
        Form {
            #if os(macOS)
            // Hidden on iOS for now: the light/dark/system override isn't
            // taking effect there yet, so the app follows the system appearance.
            Section("Appearance") {
                Picker("Theme", selection: $themeRawValue) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            #endif

            Section("Drawing") {
                Picker("Coordinate Units", selection: $coordinateDisplayUnitRawValue) {
                    ForEach(CoordinateDisplayUnit.allCases) { unit in
                        Text(unit.title).tag(unit.rawValue)
                    }
                }

                Picker("Text Font", selection: $textFontName) {
                    ForEach(DrawingTextFontPreset.allCases) { font in
                        Text(font.title).tag(font.rawValue)
                    }
                }

                HStack {
                    Slider(value: $lineThickness, in: 0.75...8.0, step: 0.25) {
                        Text("Line Thickness")
                    }
                    Text("\(lineThickness, specifier: "%.2g") px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }

                Toggle("Show Grid Marks", isOn: $showsGridMarks)
                Toggle("Show HUD", isOn: $showsHUD)
                Toggle("Select Flattened Curve Segments", isOn: $selectsCurveSegments)
            }

            Section("Light Palette") {
                PaletteEditor(
                    mode: .light,
                    presetRawValue: $lightPaletteRawValue,
                    storedColors: $lightPaletteColors
                )
            }

            Section("Dark Palette") {
                PaletteEditor(
                    mode: .dark,
                    presetRawValue: $darkPaletteRawValue,
                    storedColors: $darkPaletteColors
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Preferences")
        #if os(macOS)
        .frame(width: 500, height: 640)
        #endif
    }
}

private struct PaletteEditor: View {
    let mode: RenderColorMode
    @Binding var presetRawValue: String
    @Binding var storedColors: String

    private var basePalette: DXFRenderPalette {
        PalettePreset.stored(presetRawValue).palette(for: mode)
    }

    private var palette: DXFRenderPalette {
        basePalette.applyingStoredColors(storedColors)
    }

    var body: some View {
        Picker("Preset", selection: presetSelection) {
            ForEach(PalettePreset.allCases) { preset in
                Text(preset.title).tag(preset.rawValue)
            }
        }

        PalettePreview(palette: palette)

        ColorPicker("Background", selection: colorBinding(for: 0), supportsOpacity: true)
        ColorPicker("Grid", selection: colorBinding(for: 1), supportsOpacity: true)
        ColorPicker("Default Stroke", selection: colorBinding(for: 2), supportsOpacity: true)

        ForEach(Array(palette.layerColors.indices), id: \.self) { index in
            ColorPicker("Layer \(index + 1)", selection: colorBinding(for: index + 3), supportsOpacity: true)
        }

        Button("Reset Colors") {
            storedColors = ""
        }
    }

    private var presetSelection: Binding<String> {
        Binding {
            presetRawValue
        } set: { newValue in
            presetRawValue = newValue
            storedColors = ""
        }
    }

    private func colorBinding(for index: Int) -> Binding<Color> {
        Binding {
            palette.color(atEditableIndex: index).swiftUIColor
        } set: { newColor in
            storedColors = palette
                .replacingColor(at: index, with: RenderColor(newColor))
                .storageValue
        }
    }
}

private struct PalettePreview: View {
    let palette: DXFRenderPalette

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(palette.background.swiftUIColor)
                .frame(width: 36, height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }

            Circle()
                .fill(palette.grid.swiftUIColor)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(.secondary.opacity(0.18), lineWidth: 0.5)
                }

            Circle()
                .fill(palette.defaultStroke.swiftUIColor)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(.secondary.opacity(0.18), lineWidth: 0.5)
                }

            ForEach(Array(palette.layerColors.prefix(7).enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle()
                            .stroke(.secondary.opacity(0.18), lineWidth: 0.5)
                    }
            }
        }
        .padding(.vertical, 4)
    }
}
