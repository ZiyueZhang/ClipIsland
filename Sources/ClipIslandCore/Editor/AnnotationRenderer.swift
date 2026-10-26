import AppKit
import CoreText

/// Draws annotations into a CGContext that has already been flipped to a
/// top-left origin and scaled so 1 unit = 1 image pixel (preview ctx applies
/// its own scale factor; composite uses 1:1).
enum AnnotationRenderer {
    static func drawAll(
        _ annotations: [Annotation],
        in ctx: CGContext,
        mosaicTiles: [UUID: CGImage]
    ) {
        for annotation in annotations {
            drawOne(annotation, in: ctx, mosaicTile: mosaicTiles[annotation.id])
        }
    }

    static func drawOne(_ a: Annotation, in ctx: CGContext, mosaicTile: CGImage?) {
        switch a.kind {
        case .rectangle:
            stroke(CGPath(rect: a.rect, transform: nil), a, ctx)
        case .ellipse:
            stroke(CGPath(ellipseIn: a.rect, transform: nil), a, ctx)
        case .arrow:
            drawArrow(a, ctx)
        case .pen(let points):
            guard points.count > 1 else { break }
            let path = CGMutablePath()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            stroke(path, a, ctx)
        case .highlight:
            ctx.setFillColor(a.color.withAlphaComponent(0.35).cgColor)
            ctx.fill(a.rect)
        case .mosaic:
            if let tile = mosaicTile {
                ctx.draw(tile, in: a.rect)
            } else {
                ctx.setFillColor(NSColor.systemGray.withAlphaComponent(0.5).cgColor)
                ctx.fill(a.rect)
            }
        case .text:
            drawText(a, ctx)
        }
    }

    private static func stroke(_ path: CGPath, _ a: Annotation, _ ctx: CGContext) {
        ctx.addPath(path)
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(a.strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    private static func drawArrow(_ a: Annotation, _ ctx: CGContext) {
        let start = CGPoint(x: a.rect.minX, y: a.rect.minY)
        let end = CGPoint(x: a.rect.maxX, y: a.rect.maxY)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }
        let angle = atan2(dy, dx)
        let headLength = min(length * 0.3, a.strokeWidth * 5)
        let wing: CGFloat = .pi / 7

        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        // Arrowhead wings from the tip.
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - headLength * cos(angle - wing),
            y: end.y - headLength * sin(angle - wing)
        ))
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - headLength * cos(angle + wing),
            y: end.y - headLength * sin(angle + wing)
        ))
        stroke(path, a, ctx)
    }

    private static func drawText(_ a: Annotation, _ ctx: CGContext) {
        guard !a.text.isEmpty else { return }
        let font = CTFontCreateWithName("PingFangSC-Semibold" as CFString, a.fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: a.color,
        ]
        let attributed = NSAttributedString(string: a.text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)

        // Outline for readability.
        ctx.saveGState()
        ctx.translateBy(x: a.rect.minX, y: a.rect.minY + a.fontSize)
        ctx.scaleBy(x: 1, y: -1) // unflip locally so glyphs are upright
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

// MARK: - Preview composition

extension EditorModel {
    /// Base + annotations flattened at a preview resolution; cached until the
    /// model changes. `maxDimension` caps the longer side.
    func renderPreview(maxDimension: CGFloat) -> NSImage? {
        if let cached = previewCache,
           cached.version == renderVersion,
           cached.maxDimension == maxDimension {
            return cached.image
        }
        let iw = baseImage.width
        let ih = baseImage.height
        let longest = max(iw, ih)
        let scale = min(1, Double(maxDimension / CGFloat(longest)))
        let pw = max(1, Int(CGFloat(iw) * scale))
        let ph = max(1, Int(CGFloat(ih) * scale))

        guard let ctx = CGContext(
            data: nil, width: pw, height: ph,
            bitsPerComponent: 8, bytesPerRow: pw * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: 1, y: -1)
        let drawScale = CGFloat(pw) / CGFloat(iw)
        ctx.scaleBy(x: drawScale, y: drawScale)
        ctx.interpolationQuality = .medium
        ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: iw, height: ih))

        var tiles: [UUID: CGImage] = [:]
        for a in draftAnnotations {
            if case .mosaic = a.kind {
                if a.id == draft?.id {
                    // The in-progress mosaic changes every frame; skip the cache.
                    tiles[a.id] = EditorModel.pixelate(
                        image: baseImage, region: a.rect, blockSize: 14
                    )
                } else {
                    tiles[a.id] = mosaicTile(for: a)
                }
            }
        }
        AnnotationRenderer.drawAll(draftAnnotations, in: ctx, mosaicTiles: tiles)

        guard let cg = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: pw, height: ph))
        previewCache = (version: renderVersion, maxDimension: maxDimension, image: image)
        return image
    }

    var draftAnnotations: [Annotation] {
        if let draft { return annotations + [draft] }
        return annotations
    }
}
