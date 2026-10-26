import AppKit
import PDFKit

public enum ShapeKind: String, CaseIterable, Sendable {
    case rectangle, oval, line, arrow
}

/// Factories for the annotation types the editor creates. All geometry is in page space.
public enum Annotations {
    public static let redactionTag = "org.pagecraft.redaction"

    public static func markup(_ type: PDFAnnotationSubtype, bounds: CGRect, color: NSColor) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
        a.color = type == .highlight ? color.withAlphaComponent(0.45) : color
        return a
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
        case .line, .arrow:
            let pad = lineWidth * 4 + 4
            let bounds = rect.insetBy(dx: -pad, dy: -pad)
            let a = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
            a.startPoint = start - bounds.origin
            a.endPoint = end - bounds.origin
            a.endLineStyle = kind == .arrow ? .openArrow : .none
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
        switch a.type ?? "" {
        case "Highlight": return "Highlight"
        case "Underline": return "Underline"
        case "StrikeOut": return "Strikeout"
        case "Ink": return "Drawing"
        case "FreeText": return "Text"
        case "Text": return "Note"
        case "Square": return "Rectangle"
        case "Circle": return "Oval"
        case "Line": return a.endLineStyle == .none ? "Line" : "Arrow"
        case "Stamp": return "Stamp"
        default: return a.type ?? "Annotation"
        }
    }

    public static func markedText(_ a: PDFAnnotation, on page: PDFPage) -> String? {
        guard ["Highlight", "Underline", "StrikeOut"].contains(a.type ?? "") else { return nil }
        return page.selection(for: a.bounds)?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
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
