# DeXeF

[![CI](https://github.com/twarge/dexef/actions/workflows/ci.yml/badge.svg)](https://github.com/twarge/dexef/actions/workflows/ci.yml)

DeXeF views DXF files on Apple devices. There are many DXF viewers on the App Store, but all of them are terrible and cost too much. This one is free, and hopefully broadly functional.

More at [twarge.com/dexef](https://twarge.com/dexef).

## Features

- Pan, zoom, and inspect 2D DXF drawings on macOS, iPad, and iPhone, with trackpad and touch gestures.
- Layer sidebar with per-layer visibility toggles and entity counts.
- Coordinate readout with an adaptive reference grid and unit conversion.
- Snap to vertices, edges, and curves; select two vertices, an edge, or a curve to measure distance.
- Quick Look previews and Finder thumbnails on macOS, so DXF files preview without opening the app.
- A bundled demo document for kicking the tires.

DeXeF includes an independent DXF parser and does not bundle Autodesk code. AutoCAD and DXF are associated with Autodesk.

## Building

Open `DeXeF.xcodeproj` in Xcode 26 or later and run the `DeXeF` scheme. The app targets macOS 26 and iOS 26; the macOS Quick Look extensions target macOS 14.

App and document icons are generated into the asset catalog by:

```sh
swift Scripts/GenerateBlueprintIcons.swift
```

`Scripts/release-app.sh` builds, signs, notarizes, and packages the macOS app for direct distribution and exports the iOS App Store IPA. See `Scripts/release-app.sh --help` for credentials and options.

## Support

DeXeF is free, so don't expect any support. Please discuss and register issues here on GitHub.

## License

Apache License 2.0 — see [LICENSE](LICENSE). The bundled National Park font is licensed under the [SIL Open Font License 1.1](DeXeF/Resources/Fonts/NationalPark/OFL.txt).
