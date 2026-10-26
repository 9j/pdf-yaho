import AppKit
import PDFKit

/// An image placed on a page. PDFKit writes what `draw` produces into the annotation's appearance
/// stream when saving, so the image survives in the file and shows up in any PDF reader.
public final class ImageAnnotation: PDFAnnotation {
    public var image: NSImage?

    public convenience init(image: NSImage, bounds: CGRect) {
        self.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.image = image
    }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return super.draw(with: box, in: context) }
        context.saveGState()
        context.setAlpha(color.alphaComponent > 0 ? color.alphaComponent : 1)
        context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }

    public override func copy(with zone: NSZone? = nil) -> Any {
        let copy = ImageAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
        copy.image = image
        copy.color = color
        copy.contents = contents
        copy.userName = userName
        return copy
    }
}

/// A rubber-stamp style label ("APPROVED", "DRAFT"…) drawn as vector text with a rounded frame.
public final class TextStampAnnotation: PDFAnnotation {
    public var title = ""
    public var subtitle: String?
    public var tint: NSColor = .systemRed

    static func titleFont(_ hasSubtitle: Bool) -> NSFont { NSFont.systemFont(ofSize: hasSubtitle ? 18 : 22, weight: .heavy) }
    static let subtitleFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)

    public static func make(title: String, subtitle: String? = nil, tint: NSColor, at center: CGPoint) -> TextStampAnnotation {
        let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont(subtitle != nil), .kern: 1.5]).width
        let subtitleWidth = subtitle.map { ($0 as NSString).size(withAttributes: [.font: subtitleFont]).width } ?? 0
        let width = max(titleWidth, subtitleWidth) + 32
        let height: CGFloat = subtitle == nil ? 42 : 50
        let a = TextStampAnnotation(bounds: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                                    forType: .stamp, withProperties: nil)
        a.title = title
        a.subtitle = subtitle
        a.tint = tint
        a.contents = [title, subtitle].compactMap { $0 }.joined(separator: " · ")
        a.color = tint
        return a
    }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        let frame = bounds.insetBy(dx: 2, dy: 2)
        let path = CGPath(roundedRect: frame, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(path)
        context.setFillColor(tint.withAlphaComponent(0.08).cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(tint.cgColor)
        context.setLineWidth(2.5)
        context.strokePath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = Self.titleFont(subtitle != nil)
        let natural = (title as NSString).size(withAttributes: [.font: font, .kern: 1.5]).width
        let fitted = natural > frame.width - 16 ? NSFont.systemFont(ofSize: font.pointSize * (frame.width - 16) / natural, weight: .heavy) : font
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: fitted, .foregroundColor: tint, .kern: 1.5, .paragraphStyle: paragraph]
        let titleHeight = (title as NSString).size(withAttributes: titleAttrs).height
        if let subtitle {
            let subAttrs: [NSAttributedString.Key: Any] = [.font: Self.subtitleFont, .foregroundColor: tint, .paragraphStyle: paragraph]
            let subHeight = (subtitle as NSString).size(withAttributes: subAttrs).height
            let total = titleHeight + subHeight - 2
            let top = frame.midY + total / 2
            (title as NSString).draw(in: CGRect(x: frame.minX, y: top - titleHeight, width: frame.width, height: titleHeight), withAttributes: titleAttrs)
            (subtitle as NSString).draw(in: CGRect(x: frame.minX, y: top - total, width: frame.width, height: subHeight), withAttributes: subAttrs)
        } else {
            (title as NSString).draw(in: CGRect(x: frame.minX, y: frame.midY - titleHeight / 2, width: frame.width, height: titleHeight),
                                     withAttributes: titleAttrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    public override func copy(with zone: NSZone? = nil) -> Any {
        let copy = TextStampAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
        copy.title = title
        copy.subtitle = subtitle
        copy.tint = tint
        copy.contents = contents
        copy.color = color
        copy.userName = userName
        return copy
    }
}

public struct StampPreset: Hashable, Identifiable, Sendable {
    public let title: String
    public let hex: UInt32
    public var id: String { title }
    public var color: NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
    public static let all: [StampPreset] = [
        StampPreset(title: "APPROVED", hex: 0x1E8E3E), StampPreset(title: "COMPLETED", hex: 0x1E8E3E),
        StampPreset(title: "REVIEWED", hex: 0x1A73E8), StampPreset(title: "FOR REVIEW", hex: 0x1A73E8),
        StampPreset(title: "DRAFT", hex: 0x5F6368), StampPreset(title: "FINAL", hex: 0x5F6368),
        StampPreset(title: "CONFIDENTIAL", hex: 0xD93025), StampPreset(title: "REJECTED", hex: 0xD93025),
        StampPreset(title: "NOT APPROVED", hex: 0xD93025), StampPreset(title: "VOID", hex: 0xD93025),
        StampPreset(title: "SIGN HERE", hex: 0xE37400), StampPreset(title: "INITIAL HERE", hex: 0xE37400),
    ]
}

extension Annotations {
    /// A polyline or closed polygon, stored as ink so every reader can draw it.
    public static func polyline(_ points: [CGPoint], closed: Bool, color: NSColor, lineWidth: CGFloat) -> PDFAnnotation? {
        guard points.count >= 2 else { return nil }
        return ink(strokes: [closed ? points + [points[0]] : points], color: color, lineWidth: lineWidth)
    }

    public static func link(bounds: CGRect, url: URL) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
        a.url = url
        return a
    }

    public static func link(bounds: CGRect, to page: PDFPage) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
        a.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .cropBox).maxY))
        return a
    }

    public enum LineStyle: String, CaseIterable, Identifiable, Sendable {
        case solid = "Solid", dashed = "Dashed", dotted = "Dotted"
        case shortDashed = "Short Dashed", mediumDashed = "Medium Dashed", dashDotted = "Dash-Dotted"
        public var id: String { rawValue }

        /// The PDF dash array (user-space units) for this style; empty for solid.
        public var dashPattern: [CGFloat] {
            switch self {
            case .solid: []
            case .dotted: [1.5, 3]
            case .shortDashed: [3, 3]
            case .dashed: [6, 4]
            case .mediumDashed: [10, 5]
            case .dashDotted: [8, 3, 1.5, 3]
            }
        }
    }

    public static func lineStyle(of a: PDFAnnotation) -> LineStyle {
        guard a.border?.style == .dashed, let pattern = a.border?.dashPattern as? [NSNumber], let first = pattern.first else { return .solid }
        if pattern.count >= 4 { return .dashDotted }
        switch first.doubleValue {
        case ...2: return .dotted
        case ...4.5: return .shortDashed
        case ...7: return .dashed
        default: return .mediumDashed
        }
    }

    public static func setLineStyle(_ style: LineStyle, of a: PDFAnnotation) {
        let border = PDFBorder()
        border.lineWidth = a.border?.lineWidth ?? 1
        if style == .solid {
            border.style = .solid
        } else {
            border.style = .dashed
            border.dashPattern = style.dashPattern.map { NSNumber(value: Double($0)) }
        }
        a.border = border
    }

    // MARK: Line endings

    /// A line ending the user can choose, with the label and SF Symbol for a picker.
    public struct LineEnding: Identifiable, Hashable, Sendable {
        public let style: PDFLineStyle
        public let displayName: String
        public let symbolName: String
        public var id: Int { style.rawValue }

        public static let all: [LineEnding] = [
            LineEnding(style: .none, displayName: "None", symbolName: "minus"),
            LineEnding(style: .openArrow, displayName: "Open Arrow", symbolName: "arrow.right"),
            LineEnding(style: .closedArrow, displayName: "Closed Arrow", symbolName: "arrowtriangle.right.fill"),
            LineEnding(style: .circle, displayName: "Circle", symbolName: "circle.fill"),
            LineEnding(style: .square, displayName: "Square", symbolName: "square.fill"),
            LineEnding(style: .diamond, displayName: "Diamond", symbolName: "diamond.fill"),
        ]

        public static func of(_ style: PDFLineStyle) -> LineEnding { all.first { $0.style == style } ?? all[0] }
    }

    /// The endings offered by pickers, in display order.
    public static let supportedLineEndings: [LineEnding] = LineEnding.all

    /// Sets the start and end decoration of a line annotation; other annotation types are left alone.
    public static func setLineEndings(start: PDFLineStyle, end: PDFLineStyle, of a: PDFAnnotation) {
        guard a.type == "Line" else { return }
        a.startLineStyle = start
        a.endLineStyle = end
    }

    public static func lineEndings(of a: PDFAnnotation) -> (start: PDFLineStyle, end: PDFLineStyle) {
        (a.startLineStyle, a.endLineStyle)
    }

    /// Fill colour for rectangles and ovals; nil removes the fill.
    public static func setFill(_ color: NSColor?, of a: PDFAnnotation) {
        a.interiorColor = color
    }

    /// Moves an annotation to the top (drawn last) or bottom of its page's stack.
    public static func reorder(_ a: PDFAnnotation, on page: PDFPage, toFront: Bool) {
        let others = page.annotations.filter { $0 !== a }
        if toFront {
            page.removeAnnotation(a)
            page.addAnnotation(a)
        } else {
            others.forEach(page.removeAnnotation)
            page.removeAnnotation(a)
            page.addAnnotation(a)
            others.forEach(page.addAnnotation)
        }
    }
}

/// Saved signatures and initials: drawn strokes, an image, or typed text.
public struct SavedSignature: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case drawn, image }
    public var id = UUID()
    public var kind: Kind
    public var drawing: Signature?
    public var imagePNG: Data?
    public var isInitials = false

    public static func drawn(_ signature: Signature, initials: Bool = false) -> SavedSignature {
        SavedSignature(kind: .drawn, drawing: signature, isInitials: initials)
    }

    /// From an image file, or from typed text rendered in a handwriting font.
    public static func image(_ image: NSImage, initials: Bool = false) -> SavedSignature? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return SavedSignature(kind: .image, imagePNG: png, isInitials: initials)
    }

    public static func typed(_ text: String, font: NSFont, initials: Bool = false) -> SavedSignature? {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.08, green: 0.1, blue: 0.3, alpha: 1)]
        let size = (text as NSString).size(withAttributes: attrs)
        guard size.width > 0 else { return nil }
        let image = NSImage(size: CGSize(width: ceil(size.width) + 8, height: ceil(size.height) + 4), flipped: false) { _ in
            (text as NSString).draw(at: CGPoint(x: 4, y: 2), withAttributes: attrs)
            return true
        }
        let scaled = NSImage(size: image.size, flipped: false) { rect in image.draw(in: rect); return true }
        return Self.image(Self.rasterize(scaled, scale: 3), initials: initials)
    }

    static func rasterize(_ image: NSImage, scale: CGFloat) -> NSImage {
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return image }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: image.size)
        out.addRepresentation(rep)
        return out
    }

    public var image: NSImage? { imagePNG.flatMap(NSImage.init(data:)) }

    public var aspectRatio: CGFloat {
        switch kind {
        case .drawn: drawing?.aspectRatio ?? 3
        case .image: image.map { $0.size.width / max($0.size.height, 1) } ?? 3
        }
    }

    /// An annotation `width` points wide centred on `center`.
    public func annotation(center: CGPoint, width: CGFloat, color: NSColor) -> PDFAnnotation? {
        switch kind {
        case .drawn:
            return drawing?.annotation(center: center, width: width, color: color)
        case .image:
            guard let image else { return nil }
            let height = width / aspectRatio
            return ImageAnnotation(image: image, bounds: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
        }
    }
}

public enum SignatureLibrary {
    static let key = "org.pagecraft.signatures"

    public static func load(_ defaults: UserDefaults = .standard) -> [SavedSignature] {
        if let data = defaults.data(forKey: key), let list = try? JSONDecoder().decode([SavedSignature].self, from: data) { return list }
        // Migrate the single signature saved by earlier versions.
        return SignatureStore.load(defaults).map { [.drawn($0)] } ?? []
    }

    public static func save(_ list: [SavedSignature], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
        SignatureStore.save(nil, defaults)
    }
}
