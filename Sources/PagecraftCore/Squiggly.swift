import AppKit
import PDFKit

/// A wavy underline. PDFKit stores a `/Squiggly` annotation but never draws it (it writes no appearance
/// stream), so this subclass draws the wave itself; what `draw` produces is written into the appearance
/// stream on save, which makes it show up in other readers and after reopening.
public final class SquigglyAnnotation: PDFAnnotation {
    public static let subtype = PDFAnnotationSubtype(rawValue: "Squiggly")

    public convenience init(bounds: CGRect, color: NSColor) {
        self.init(bounds: bounds, forType: Self.subtype, withProperties: nil)
        self.color = color
    }

    /// Zig-zag wave along the bottom edge of `rect`; amplitude scales with the height.
    static func wavePath(in rect: CGRect) -> CGPath {
        let amplitude = min(max(rect.height * 0.12, 1), 2.5)
        let step = amplitude * 1.6
        let baseline = rect.minY + amplitude + 0.75
        let path = CGMutablePath()
        var x = rect.minX
        path.move(to: CGPoint(x: x, y: baseline))
        var up = true
        while x < rect.maxX {
            x = min(x + step, rect.maxX)
            path.addLine(to: CGPoint(x: x, y: baseline + (up ? amplitude : -amplitude)))
            up.toggle()
        }
        return path
    }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.withAlphaComponent(1).cgColor)
        context.setLineWidth(1.1)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(Self.wavePath(in: bounds))
        context.strokePath()
        context.restoreGState()
    }

    public override func copy(with zone: NSZone? = nil) -> Any {
        let copy = SquigglyAnnotation(bounds: bounds, color: color)
        copy.contents = contents
        copy.userName = userName
        return copy
    }
}

extension Annotations {
    /// A wavy underline along the bottom of `bounds` (select text, pass the selection's line bounds).
    public static func squiggly(bounds: CGRect, color: NSColor) -> PDFAnnotation {
        SquigglyAnnotation(bounds: bounds, color: color)
    }
}
