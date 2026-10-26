import AppKit
import PDFKit

/// Custom annotation state is kept in extra dictionary keys so a callout or cloud saved to disk can be
/// turned back into an editable object after reopening (see `Annotations.restoreCustomAnnotations`).
/// The key names are part of saved files, so they keep the project's original name.
enum CustomKeys {
    static let kind = PDFAnnotationKey(rawValue: "PagecraftKind")
    static let geometry = PDFAnnotationKey(rawValue: "PagecraftGeometry")
    static let fontSize = PDFAnnotationKey(rawValue: "PagecraftFontSize")

    static func format(_ points: [CGPoint]) -> String { points.map { "\($0.x),\($0.y)" }.joined(separator: ";") }
    static func parse(_ text: String) -> [CGPoint]? {
        let points: [CGPoint] = text.split(separator: ";").compactMap { pair in
            let v = pair.split(separator: ",").compactMap { Double($0) }
            return v.count == 2 ? CGPoint(x: v[0], y: v[1]) : nil
        }
        return points.isEmpty ? nil : points
    }
}

/// A text box with a leader line that ends in an arrow at `anchor`.
///
/// It is one annotation: the bounds enclose the box and the anchor, and everything is drawn by `draw`,
/// which PDFKit writes into the appearance stream on save, so it looks the same in any reader and after
/// reopening. Box and anchor are stored relative to the bounds origin, so moving the annotation moves both.
public final class CalloutAnnotation: PDFAnnotation {
    static let padding: CGFloat = 6
    static let arrowLength: CGFloat = 9

    /// Box and anchor relative to `bounds.origin`.
    private var relativeBox = CGRect.zero
    private var relativeAnchor = CGPoint.zero

    public var fontSize: CGFloat = 12 {
        didSet { persist() }
    }

    /// The text shown in the box.
    public var text: String {
        get { contents ?? "" }
        set { contents = newValue }
    }

    /// The text box in page space.
    public var box: CGRect { relativeBox.offsetBy(dx: bounds.minX, dy: bounds.minY) }

    /// The point the leader arrow touches, in page space. Setting it grows or shrinks the bounds; the box stays put.
    public var anchor: CGPoint {
        get { relativeAnchor + bounds.origin }
        set { layout(box: box, anchor: newValue) }
    }

    /// Moves the text box, keeping the anchor where it is on the page.
    public func setBox(_ newBox: CGRect) { layout(box: newBox, anchor: anchor) }

    public static func make(text: String, box: CGRect, anchor: CGPoint, color: NSColor, fontSize: CGFloat = 12) -> CalloutAnnotation {
        let a = CalloutAnnotation(bounds: frame(box: box, anchor: anchor), forType: .stamp, withProperties: nil)
        a.color = color
        a.fontSize = fontSize
        a.contents = text
        a.layout(box: box, anchor: anchor)
        return a
    }

    static func frame(box: CGRect, anchor: CGPoint) -> CGRect {
        box.union(CGRect(origin: anchor, size: .zero)).insetBy(dx: -padding, dy: -padding)
    }

    private func layout(box: CGRect, anchor: CGPoint) {
        let frame = Self.frame(box: box, anchor: anchor)
        bounds = frame
        relativeBox = box.offsetBy(dx: -frame.minX, dy: -frame.minY)
        relativeAnchor = anchor - frame.origin
        persist()
    }

    /// Scales and moves the box the way the bounds moved; the anchor stays put on the page.
    func resize(to newBounds: CGRect) {
        let old = bounds, oldBox = box, pageAnchor = anchor
        guard old.width > 0, old.height > 0, newBounds.width > 0, newBounds.height > 0 else { return }
        let sx = newBounds.width / old.width, sy = newBounds.height / old.height
        let newBox = CGRect(x: newBounds.minX + (oldBox.minX - old.minX) * sx, y: newBounds.minY + (oldBox.minY - old.minY) * sy,
                            width: max(oldBox.width * sx, 8), height: max(oldBox.height * sy, 8))
        layout(box: newBox, anchor: pageAnchor)
    }

    private func persist() {
        setValue("callout", forAnnotationKey: CustomKeys.kind)
        setValue(CustomKeys.format([relativeBox.origin, CGPoint(x: relativeBox.width, y: relativeBox.height), relativeAnchor]),
                 forAnnotationKey: CustomKeys.geometry)
        setValue(String(describing: Double(fontSize)), forAnnotationKey: CustomKeys.fontSize)
    }

    /// Where the leader leaves the box: the box edge on the line towards the anchor, nil when the anchor is inside.
    static func leaderStart(box: CGRect, anchor: CGPoint) -> CGPoint? {
        let c = CGPoint(x: box.midX, y: box.midY)
        let dx = anchor.x - c.x, dy = anchor.y - c.y
        guard dx != 0 || dy != 0 else { return nil }
        let tx = dx == 0 ? CGFloat.infinity : (box.width / 2) / abs(dx)
        let ty = dy == 0 ? CGFloat.infinity : (box.height / 2) / abs(dy)
        let t = min(tx, ty)
        return t < 1 ? CGPoint(x: c.x + dx * t, y: c.y + dy * t) : nil
    }

    public override func draw(with displayBox: PDFDisplayBox, in context: CGContext) {
        let box = self.box, anchor = self.anchor
        let stroke = color.withAlphaComponent(1)
        context.saveGState()
        context.setStrokeColor(stroke.cgColor)
        context.setFillColor(stroke.cgColor)
        context.setLineWidth(1.25)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        if let start = Self.leaderStart(box: box, anchor: anchor) {
            let angle = atan2(anchor.y - start.y, anchor.x - start.x)
            let length = min(Self.arrowLength, hypot(anchor.x - start.x, anchor.y - start.y))
            let base = CGPoint(x: anchor.x - cos(angle) * length, y: anchor.y - sin(angle) * length)
            context.move(to: start)
            context.addLine(to: base)
            context.strokePath()
            let half: CGFloat = length * 0.4
            context.move(to: anchor)
            context.addLine(to: CGPoint(x: base.x - sin(angle) * half, y: base.y + cos(angle) * half))
            context.addLine(to: CGPoint(x: base.x + sin(angle) * half, y: base.y - cos(angle) * half))
            context.closePath()
            context.fillPath()
        }

        let frame = CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil)
        context.addPath(frame)
        context.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        context.fillPath()
        context.addPath(frame)
        context.strokePath()

        context.addPath(frame)
        context.clip()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (text as NSString).draw(in: box.insetBy(dx: 5, dy: 3),
                                withAttributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: stroke])
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    public override func copy(with zone: NSZone? = nil) -> Any {
        let copy = CalloutAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
        copy.color = color
        copy.contents = contents
        copy.userName = userName
        copy.relativeBox = relativeBox
        copy.relativeAnchor = relativeAnchor
        copy.fontSize = fontSize
        copy.persist()
        return copy
    }

    /// Rebuilds an editable callout from one that was saved and reopened (a plain stamp carrying our keys).
    static func restore(from a: PDFAnnotation) -> CalloutAnnotation? {
        guard a.value(forAnnotationKey: CustomKeys.kind) as? String == "callout",
              let geometry = (a.value(forAnnotationKey: CustomKeys.geometry) as? String).flatMap(CustomKeys.parse), geometry.count == 3
        else { return nil }
        let restored = CalloutAnnotation(bounds: a.bounds, forType: .stamp, withProperties: nil)
        restored.color = a.color
        restored.contents = a.contents
        restored.userName = a.userName
        restored.relativeBox = CGRect(origin: geometry[0], size: CGSize(width: geometry[1].x, height: geometry[1].y))
        restored.relativeAnchor = geometry[2]
        if let size = (a.value(forAnnotationKey: CustomKeys.fontSize) as? String).flatMap(Double.init) { restored.fontSize = CGFloat(size) }
        restored.persist()
        return restored
    }
}

extension Annotations {
    /// Turns callouts and clouds that came back from disk as plain stamps into editable objects again.
    /// Returns how many were replaced.
    @discardableResult
    public static func restoreCustomAnnotations(on page: PDFPage) -> Int {
        let all = page.annotations
        let replaced: [PDFAnnotation] = all.map { a in
            if a is CalloutAnnotation || a is CloudAnnotation { return a }
            return CalloutAnnotation.restore(from: a) ?? CloudAnnotation.restore(from: a) ?? a
        }
        guard let first = all.indices.first(where: { all[$0] !== replaced[$0] }) else { return 0 }
        for a in all[first...] { page.removeAnnotation(a) }
        for a in replaced[first...] { page.addAnnotation(a) }
        return zip(all, replaced).filter { $0 !== $1 }.count
    }
}
