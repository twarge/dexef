// Copyright (C) 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum DXFPreviewDrawing {
    static let fallbackSize = CGSize(width: 1000, height: 720)

    static func scene(from url: URL) throws -> DXFScene {
        let data = try Data(contentsOf: url)
        let text = decode(data: data)
        return DXFParser.parse(text)
    }

    static func preferredSize(for scene: DXFScene, maxDimension: CGFloat = 1200) -> CGSize {
        let geometry = GeometryBuilder.build(scene: scene, visibleLayers: visibleLayerNames(for: scene), palette: .standardDark)
        guard let bounds = geometry.bounds else {
            return fallbackSize
        }

        let width = CGFloat(bounds.width)
        let height = CGFloat(bounds.height)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            return fallbackSize
        }

        if width >= height {
            return CGSize(width: maxDimension, height: max(420, maxDimension * height / width))
        }

        return CGSize(width: max(420, maxDimension * width / height), height: maxDimension)
    }

    static func pdfData(for scene: DXFScene, size: CGSize) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            return Data()
        }

        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        context.beginPDFPage(nil)
        draw(scene: scene, in: mediaBox, context: context, style: .preview)
        context.endPDFPage()
        context.closePDF()

        return data as Data
    }

    static func draw(scene: DXFScene, in rect: CGRect, context: CGContext, style: Style) {
        let drawingRect = style.drawingRect(in: rect)
        drawBackground(in: rect, drawingRect: drawingRect, context: context, style: style)

        let geometry = GeometryBuilder.build(scene: scene, visibleLayers: visibleLayerNames(for: scene), palette: style.palette)
        guard let bounds = geometry.bounds,
              !geometry.segments.isEmpty || !geometry.points.isEmpty || !geometry.filledPolygons.isEmpty || !geometry.textSprites.isEmpty else {
            drawEmptyGlyph(in: drawingRect, context: context, style: style)
            return
        }

        context.saveGState()
        context.clip(to: drawingRect)
        applyGeometryTransform(bounds: bounds, drawingRect: drawingRect, context: context)

        let screenLineWidth = style.lineThickness
        let lineWidth = screenLineWidth / drawingScale(bounds: bounds, drawingRect: drawingRect)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(lineWidth)

        for polygon in geometry.filledPolygons {
            context.beginPath()
            for loop in polygon.boundaryLoops where loop.count >= 3 {
                guard let first = loop.first else { continue }
                context.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
                for point in loop.dropFirst() {
                    context.addLine(to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
                }
                context.closePath()
            }
            context.setFillColor(cgColor(for: polygon.color, style: style))
            context.fillPath(using: .evenOdd)
        }

        for segment in geometry.segments {
            context.setStrokeColor(cgColor(for: segment.color, style: style))
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(segment.start.x), y: CGFloat(segment.start.y)))
            context.addLine(to: CGPoint(x: CGFloat(segment.end.x), y: CGFloat(segment.end.y)))
            context.strokePath()
        }

        for point in geometry.points {
            context.setFillColor(cgColor(for: point.color, style: style))
            context.fillEllipse(in: CGRect(
                x: CGFloat(point.center.x) - lineWidth * 0.5,
                y: CGFloat(point.center.y) - lineWidth * 0.5,
                width: lineWidth,
                height: lineWidth
            ))
        }

        drawTextSprites(geometry.textSprites, context: context, style: style)

        context.restoreGState()
    }

    enum Style {
        case preview
        case thumbnail

        var palette: DXFRenderPalette {
            switch self {
            case .preview: return .standardDark
            case .thumbnail: return .standardLight
            }
        }

        var lineThickness: CGFloat {
            switch self {
            case .preview: return CGFloat(DXFRenderStyle.defaultLineThickness)
            case .thumbnail: return 1.8
            }
        }

        func drawingRect(in rect: CGRect) -> CGRect {
            switch self {
            case .preview:
                return rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.08)
            case .thumbnail:
                return rect.insetBy(dx: max(10, rect.width * 0.13), dy: max(10, rect.height * 0.14))
            }
        }
    }

    private static func drawBackground(in rect: CGRect, drawingRect: CGRect, context: CGContext, style: Style) {
        switch style {
        case .preview:
            context.setFillColor(style.palette.background.cgColor)
            context.fill(rect)

        case .thumbnail:
            let radius = min(rect.width, rect.height) * 0.08
            let pageRect = rect.insetBy(dx: max(2, rect.width * 0.04), dy: max(2, rect.height * 0.04))
            let pagePath = CGPath(roundedRect: pageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            context.addPath(pagePath)
            context.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0))
            context.fillPath()

            context.addPath(pagePath)
            context.setStrokeColor(CGColor(red: 0.70, green: 0.75, blue: 0.82, alpha: 1.0))
            context.setLineWidth(max(1.0, min(rect.width, rect.height) * 0.008))
            context.strokePath()

            let badgeHeight = max(16, rect.height * 0.18)
            let badgeWidth = max(34, rect.width * 0.32)
            let badgeRect = CGRect(
                x: pageRect.minX + max(6, rect.width * 0.06),
                y: pageRect.minY + max(6, rect.height * 0.06),
                width: badgeWidth,
                height: badgeHeight
            )
            let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: badgeHeight * 0.28, cornerHeight: badgeHeight * 0.28, transform: nil)
            context.addPath(badgePath)
            context.setFillColor(CGColor(red: 0.10, green: 0.22, blue: 0.38, alpha: 1.0))
            context.fillPath()

            drawText("DXF", in: badgeRect, context: context, fontSize: badgeHeight * 0.48, color: CGColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 1.0))

            context.setStrokeColor(CGColor(red: 0.78, green: 0.84, blue: 0.91, alpha: 0.28))
            context.setLineWidth(max(0.5, min(rect.width, rect.height) * 0.003))
            let gridStep = max(12, min(drawingRect.width, drawingRect.height) / 5)
            var x = drawingRect.minX
            while x <= drawingRect.maxX {
                context.move(to: CGPoint(x: x, y: drawingRect.minY))
                context.addLine(to: CGPoint(x: x, y: drawingRect.maxY))
                x += gridStep
            }
            var y = drawingRect.minY
            while y <= drawingRect.maxY {
                context.move(to: CGPoint(x: drawingRect.minX, y: y))
                context.addLine(to: CGPoint(x: drawingRect.maxX, y: y))
                y += gridStep
            }
            context.strokePath()
        }
    }

    private static func drawEmptyGlyph(in rect: CGRect, context: CGContext, style: Style) {
        let glyphRect = rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25)
        context.setStrokeColor(style == .preview
            ? CGColor(red: 0.80, green: 0.86, blue: 0.94, alpha: 0.7)
            : CGColor(red: 0.30, green: 0.43, blue: 0.60, alpha: 0.65)
        )
        context.setLineWidth(max(1, min(rect.width, rect.height) * 0.025))
        context.stroke(glyphRect)
        drawText("DXF", in: glyphRect, context: context, fontSize: min(glyphRect.width, glyphRect.height) * 0.26, color: style == .preview
            ? CGColor(red: 0.86, green: 0.90, blue: 0.96, alpha: 0.85)
            : CGColor(red: 0.18, green: 0.30, blue: 0.46, alpha: 0.85)
        )
    }

    private static func drawText(_ text: String, in rect: CGRect, context: CGContext, fontSize: CGFloat, color: CGColor) {
        #if os(macOS)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor(cgColor: color) ?? .labelColor,
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = CGRect(
            x: rect.midX - textSize.width * 0.5,
            y: rect.midY - textSize.height * 0.5,
            width: textSize.width,
            height: textSize.height
        )

        context.saveGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributedText.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
        #else
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor(cgColor: color),
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = CGRect(
            x: rect.midX - textSize.width * 0.5,
            y: rect.midY - textSize.height * 0.5,
            width: textSize.width,
            height: textSize.height
        )

        UIGraphicsPushContext(context)
        attributedText.draw(in: textRect)
        UIGraphicsPopContext()
        #endif
    }

    private static func applyGeometryTransform(bounds: DXFBounds, drawingRect: CGRect, context: CGContext) {
        let scale = drawingScale(bounds: bounds, drawingRect: drawingRect)
        let center = bounds.center

        context.translateBy(x: drawingRect.midX, y: drawingRect.midY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -CGFloat(center.x), y: -CGFloat(center.y))
    }

    private static func drawingScale(bounds: DXFBounds, drawingRect: CGRect) -> CGFloat {
        let scaleX = drawingRect.width / CGFloat(bounds.width)
        let scaleY = drawingRect.height / CGFloat(bounds.height)
        return max(0.0001, min(scaleX, scaleY))
    }

    private static func drawTextSprites(_ sprites: [RenderTextSprite], context: CGContext, style: Style) {
        for sprite in sprites {
            guard sprite.vertices.count >= 6 else { continue }

            let bottomLeft = sprite.vertices[0].position
            let bottomRight = sprite.vertices[1].position
            let topLeft = sprite.vertices[5].position
            let color = sprite.vertices[0].color
            let rect = CGRect(x: 0, y: 0, width: 1, height: 1)

            context.saveGState()
            context.concatenate(CGAffineTransform(
                a: CGFloat(bottomRight.x - bottomLeft.x),
                b: CGFloat(bottomRight.y - bottomLeft.y),
                c: CGFloat(topLeft.x - bottomLeft.x),
                d: CGFloat(topLeft.y - bottomLeft.y),
                tx: CGFloat(bottomLeft.x),
                ty: CGFloat(bottomLeft.y)
            ))
            context.clip(to: rect, mask: sprite.image)
            context.setFillColor(cgColor(for: color, style: style))
            context.fill(rect)
            context.restoreGState()
        }
    }

    private static func cgColor(for color: SIMD4<Float>, style: Style) -> CGColor {
        if style == .thumbnail {
            let luminance = CGFloat(color.x) * 0.2126 + CGFloat(color.y) * 0.7152 + CGFloat(color.z) * 0.0722
            if luminance > 0.78 {
                return CGColor(red: CGFloat(color.x) * 0.55, green: CGFloat(color.y) * 0.55, blue: CGFloat(color.z) * 0.65, alpha: CGFloat(color.w))
            }
        }

        return CGColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w))
    }

    private static func visibleLayerNames(for scene: DXFScene) -> Set<String> {
        let defaultVisible = scene.layers.filter(\.isVisibleByDefault).map(\.name)
        if defaultVisible.isEmpty {
            return Set(scene.layers.map(\.name))
        }
        return Set(defaultVisible)
    }

    private static func decode(data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }
}
