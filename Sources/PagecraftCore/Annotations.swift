import AppKit
import PDFKit

public enum ShapeKind: String, CaseIterable, Sendable {
    case rectangle, oval, line, arrow, doubleArrow
}

/// Factories for the annotation types the editor creates. All geometry is in page space.
public enum Annotations {
    public static let redactionTag = "org.pagecraft.redaction"

    public static func markup(_ type: PDFAnnotationSubtype, bounds: CGRect, color: NSColor) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
        a.color = type == .highlight ? color.withAlphaComponent(0.45) : color
        return a
    }

    /// One markup annotation covering several lines: bounds are their union and each line is a
    /// quadrilateral (relative to the bounds origin), so a multi-line highlight is a single object.
    public static func markup(_ type: PDFAnnotationSubtype, lines: [CGRect], color: NSColor) -> PDFAnnotation? {
        guard let first = lines.first else { return nil }
        let union = lines.dropFirst().reduce(first) { $0.union($1) }
        let a = markup(type, bounds: union, color: color)
        a.quadrilateralPoints = lines.flatMap { r in
            [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)]
                .map { NSValue(point: CGPoint(x: $0.x - union.minX, y: $0.y - union.minY)) }
        }
        return a
    }

    /// The line rectangles of a markup annotation in page space (its quadrilaterals, else its bounds).
    public static func lineRects(of a: PDFAnnotation) -> [CGRect] {
        let points = (a.quadrilateralPoints ?? []).map { $0.pointValue }
        guard points.count >= 4, points.count % 4 == 0 else { return [a.bounds] }
        return stride(from: 0, to: points.count, by: 4).map { i in
            let quad = points[i..<(i + 4)]
            let xs = quad.map(\.x), ys = quad.map(\.y)
            return CGRect(x: xs.min()! + a.bounds.minX, y: ys.min()! + a.bounds.minY,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
    }

    /// Ink paths in PDFKit are relative to the annotation's bounds origin.
    public static func ink(strokes: [[CGPoint]], color: NSColor, lineWidth: CGFloat) -> PDFAnnotation? {
        let all = strokes.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max()
        else { return nil }
        let pad = max(lineWidth * 2, 2)
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -pad, dy: -pad)
        let a = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        for stroke in strokes where !stroke.isEmpty {
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: stroke[0] - bounds.origin)
            for point in stroke.dropFirst() { path.line(to: point - bounds.origin) }
            if stroke.count == 1 { path.line(to: stroke[0] - bounds.origin + CGPoint(x: 0.1, y: 0.1)) }
            a.add(path)
        }
        a.color = color
        a.border = border(lineWidth)
        return a
    }

    public static func shape(_ kind: ShapeKind, from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) -> PDFAnnotation {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        switch kind {
        case .rectangle, .oval:
            let a = PDFAnnotation(bounds: rect, forType: kind == .rectangle ? .square : .circle, withProperties: nil)
            a.color = color
            a.border = border(lineWidth)
            return a
        case .line, .arrow, .doubleArrow:
            let pad = lineWidth * 4 + 4
            let bounds = rect.insetBy(dx: -pad, dy: -pad)
            let a = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
            a.startPoint = start - bounds.origin
            a.endPoint = end - bounds.origin
            a.endLineStyle = kind == .line ? .none : .openArrow
            a.startLineStyle = kind == .doubleArrow ? .openArrow : .none
            a.color = color
            a.border = border(lineWidth)
            return a
        }
    }

    public static func freeText(_ text: String, at topLeft: CGPoint, color: NSColor, fontSize: CGFloat) -> PDFAnnotation {
        let font = NSFont.systemFont(ofSize: fontSize)
        let size = (text as NSString).boundingRect(with: CGSize(width: 400, height: 10_000),
                                                   options: [.usesLineFragmentOrigin], attributes: [.font: font]).size
        let rect = CGRect(x: topLeft.x, y: topLeft.y - size.height - 6, width: ceil(size.width) + 12, height: ceil(size.height) + 6)
        let a = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        a.contents = text
        a.font = font
        a.fontColor = color
        a.color = .clear
        a.border = border(0)
        return a
    }

    public static func note(_ text: String, at point: CGPoint, color: NSColor) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20), forType: .text, withProperties: nil)
        a.contents = text
        a.color = color
        a.iconType = .comment
        return a
    }

    public static func redaction(bounds: CGRect) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
        a.color = .black
        a.interiorColor = .black
        a.userName = redactionTag
        return a
    }

    public static func isRedaction(_ a: PDFAnnotation) -> Bool { a.userName == redactionTag }

    /// Annotations the user owns (as opposed to form widgets, links and popups).
    public static func isUserEditable(_ a: PDFAnnotation) -> Bool {
        guard let type = a.type else { return false }
        return !["Widget", "Link", "Popup"].contains(type)
    }

    public static func isMovable(_ a: PDFAnnotation) -> Bool {
        guard let type = a.type else { return false }
        return ["FreeText", "Square", "Circle", "Ink", "Line", "Stamp", "Text"].contains(type)
    }

    public static func displayName(_ a: PDFAnnotation) -> String {
        if isRedaction(a) { return "Redaction" }
        if a is CalloutAnnotation { return "Callout" }
        if a is CloudAnnotation { return "Cloud" }
        switch a.type ?? "" {
        case "Highlight": return "Highlight"
        case "Underline": return "Underline"
        case "StrikeOut": return "Strikeout"
        case "Squiggly": return "Squiggly"
        case "Ink": return "Drawing"
        case "FreeText": return "Text"
        case "Text": return "Note"
        case "Square": return "Rectangle"
        case "Circle": return "Oval"
        case "Line": return a.endLineStyle == .none ? "Line" : a.startLineStyle == .none ? "Arrow" : "Double Arrow"
        case "Link": return "Link"
        case "Stamp": return "Stamp"
        default: return a.type ?? "Annotation"
        }
    }

    public static func markedText(_ a: PDFAnnotation, on page: PDFPage) -> String? {
        guard ["Highlight", "Underline", "StrikeOut", "Squiggly"].contains(a.type ?? "") else { return nil }
        return lineRects(of: a).compactMap { page.selection(for: $0.insetBy(dx: 0, dy: $0.height * 0.2))?.string }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    public static func isMarkup(_ a: PDFAnnotation) -> Bool {
        ["Highlight", "Underline", "StrikeOut", "Squiggly"].contains(a.type ?? "")
    }

    /// Annotations whose box can be resized by dragging a corner.
    public static func isResizable(_ a: PDFAnnotation) -> Bool {
        a is CalloutAnnotation || a is CloudAnnotation || ["FreeText", "Square", "Circle", "Ink", "Line"].contains(a.type ?? "")
    }

    /// The colour the user perceives: text colour for text boxes, stroke colour otherwise.
    public static func color(of a: PDFAnnotation) -> NSColor {
        if a.type == "FreeText" { return a.fontColor ?? .black }
        return a.color.withAlphaComponent(1)
    }

    public static func setColor(_ color: NSColor, of a: PDFAnnotation) {
        if isRedaction(a) { return }
        switch a.type ?? "" {
        case "FreeText": a.fontColor = color
        case "Highlight": a.color = color.withAlphaComponent(0.45)
        default: a.color = color
        }
    }

    /// Moves and scales an annotation into `newBounds`, scaling ink paths and line endpoints with it.
    public static func resize(_ a: PDFAnnotation, to newBounds: CGRect) {
        if let callout = a as? CalloutAnnotation { callout.resize(to: newBounds); return }
        if let cloud = a as? CloudAnnotation { cloud.resize(to: newBounds); return }
        let old = a.bounds
        guard old.width > 0, old.height > 0, newBounds.width > 0, newBounds.height > 0 else { a.bounds = newBounds; return }
        let sx = newBounds.width / old.width, sy = newBounds.height / old.height
        switch a.type ?? "" {
        case "Ink":
            let paths = a.paths ?? []
            for path in paths { a.remove(path) }
            a.bounds = newBounds
            for path in paths {
                let scaled = path.copy() as! NSBezierPath
                scaled.transform(using: AffineTransform(scaleByX: sx, byY: sy))
                a.add(scaled)
            }
        case "Line":
            let start = a.startPoint, end = a.endPoint
            a.bounds = newBounds
            a.startPoint = CGPoint(x: start.x * sx, y: start.y * sy)
            a.endPoint = CGPoint(x: end.x * sx, y: end.y * sy)
        default:
            a.bounds = newBounds
        }
    }

    /// A copy offset by `offset`, for Duplicate.
    public static func duplicate(_ a: PDFAnnotation, offset: CGPoint = CGPoint(x: 12, y: -12)) -> PDFAnnotation? {
        guard let copy = a.copy() as? PDFAnnotation else { return nil }
        copy.bounds = a.bounds.offsetBy(dx: offset.x, dy: offset.y)
        if let paths = a.paths, copy.paths?.isEmpty ?? true { paths.forEach { copy.add($0.copy() as! NSBezierPath) } }
        return copy
    }

    static func border(_ width: CGFloat) -> PDFBorder {
        let b = PDFBorder()
        b.lineWidth = width
        return b
    }
}

extension CGPoint {
    public static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    public static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
}
