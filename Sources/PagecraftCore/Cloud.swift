import AppKit
import PDFKit

/// A "revision cloud": a closed polygon whose edges are replaced by a row of scallops. It is drawn by
/// `draw`, so PDFKit writes it into the appearance stream on save and every reader shows it.
/// The polygon is stored relative to the bounds origin, so moving the annotation moves the cloud.
public final class CloudAnnotation: PDFAnnotation {
    /// Polygon vertices relative to `bounds.origin`.
    private var relativeVertices: [CGPoint] = []
    /// Space between the polygon's bounding box and the bounds, so the scallops stay inside.
    private var inset: CGFloat = 0
    private var scallop: CGFloat = 14

    /// The polygon in page space.
    public var vertices: [CGPoint] { relativeVertices.map { $0 + bounds.origin } }

    public var lineWidth: CGFloat { border?.lineWidth ?? 1 }

    /// Fill colour inside the cloud; nil for none.
    public var fillColor: NSColor? {
        get { interiorColor }
        set { interiorColor = newValue }
    }

    static func scallopSize(lineWidth: CGFloat) -> CGFloat { max(10, lineWidth * 6) }

    public static func make(points: [CGPoint], color: NSColor, lineWidth: CGFloat, fill: NSColor? = nil) -> CloudAnnotation? {
        guard points.count >= 3,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              maxX > minX || maxY > minY
        else { return nil }
        let size = scallopSize(lineWidth: lineWidth)
        let inset = size / 2 + lineWidth + 1
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -inset, dy: -inset)
        let a = CloudAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
        a.relativeVertices = points.map { $0 - bounds.origin }
        a.inset = inset
        a.scallop = size
        a.color = color
        a.border = Annotations.border(lineWidth)
        if let fill { a.interiorColor = fill }
        a.persist()
        return a
    }

    /// Moves and scales the cloud into `newBounds`; scallops keep their size and are redistributed along the edges.
    func resize(to newBounds: CGRect) {
        let old = bounds
        let oldInner = old.insetBy(dx: inset, dy: inset), newInner = newBounds.insetBy(dx: inset, dy: inset)
        guard newInner.width > 0, newInner.height > 0 else { bounds = newBounds; return }
        let sx = oldInner.width > 0 ? newInner.width / oldInner.width : 1
        let sy = oldInner.height > 0 ? newInner.height / oldInner.height : 1
        // Work in page space so the shared origin shift is applied once.
        let mapped = vertices.map {
            CGPoint(x: newInner.minX + ($0.x - oldInner.minX) * sx, y: newInner.minY + ($0.y - oldInner.minY) * sy)
        }
        bounds = newBounds
        relativeVertices = mapped.map { $0 - newBounds.origin }
        persist()
    }

    /// The scalloped outline of `polygon`. Every edge becomes one or more arcs bulging away from the inside.
    static func outline(of polygon: [CGPoint], scallop: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard polygon.count >= 3 else { return path }
        var area: CGFloat = 0
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            area += p.x * q.y - q.x * p.y
        }
        let outward: CGFloat = area >= 0 ? 1 : -1  // counter-clockwise polygons have their outside on the right
        path.move(to: polygon[0])
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            let length = hypot(q.x - p.x, q.y - p.y)
            guard length > 0.01 else { continue }
            let count = max(1, Int((length / scallop).rounded()))
            let ux = (q.x - p.x) / length, uy = (q.y - p.y) / length
            let nx = uy * outward, ny = -ux * outward
            let chord = length / CGFloat(count)
            for k in 0..<count {
                let a = CGPoint(x: p.x + ux * chord * CGFloat(k), y: p.y + uy * chord * CGFloat(k))
                let mid = CGPoint(x: a.x + ux * chord / 2, y: a.y + uy * chord / 2)
                let r = chord / 2
                let steps = 10
                for s in 1...steps {
                    let theta = CGFloat.pi * CGFloat(s) / CGFloat(steps)
                    path.addLine(to: CGPoint(x: mid.x - r * cos(theta) * ux + r * sin(theta) * nx,
                                             y: mid.y - r * cos(theta) * uy + r * sin(theta) * ny))
                }
            }
        }
        path.closeSubpath()
        return path
    }

    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let path = Self.outline(of: vertices, scallop: scallop)
        context.saveGState()
        if let fill = interiorColor, fill.alphaComponent > 0 {
            context.addPath(path)
            context.setFillColor(fill.cgColor)
            context.fillPath()
        }
        context.addPath(path)
        context.setStrokeColor(color.withAlphaComponent(1).cgColor)
        context.setLineWidth(max(lineWidth, 0.5))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        if border?.style == .dashed, let pattern = border?.dashPattern as? [NSNumber], !pattern.isEmpty {
            context.setLineDash(phase: 0, lengths: pattern.map { CGFloat($0.doubleValue) })
        }
        context.strokePath()
        context.restoreGState()
    }

    private func persist() {
        setValue("cloud", forAnnotationKey: CustomKeys.kind)
        setValue(CustomKeys.format([CGPoint(x: inset, y: scallop)] + relativeVertices), forAnnotationKey: CustomKeys.geometry)
    }

    public override func copy(with zone: NSZone? = nil) -> Any {
        let copy = CloudAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
        copy.color = color
        copy.contents = contents
        copy.userName = userName
        copy.interiorColor = interiorColor
        copy.border = Annotations.border(lineWidth)
        if let style = border?.style, style == .dashed {
            copy.border?.style = .dashed
            copy.border?.dashPattern = border?.dashPattern
        }
        copy.relativeVertices = relativeVertices
        copy.inset = inset
        copy.scallop = scallop
        copy.persist()
        return copy
    }

    static func restore(from a: PDFAnnotation) -> CloudAnnotation? {
        guard a.value(forAnnotationKey: CustomKeys.kind) as? String == "cloud",
              let geometry = (a.value(forAnnotationKey: CustomKeys.geometry) as? String).flatMap(CustomKeys.parse), geometry.count >= 4
        else { return nil }
        let restored = CloudAnnotation(bounds: a.bounds, forType: .stamp, withProperties: nil)
        restored.color = a.color
        restored.contents = a.contents
        restored.userName = a.userName
        restored.interiorColor = a.interiorColor
        restored.border = a.border
        restored.inset = geometry[0].x
        restored.scallop = geometry[0].y
        restored.relativeVertices = Array(geometry.dropFirst())
        restored.persist()
        return restored
    }
}

extension Annotations {
    /// A scalloped revision cloud around `rect`; `fill` is optional.
    public static func cloud(rect: CGRect, color: NSColor, lineWidth: CGFloat, fill: NSColor? = nil) -> PDFAnnotation {
        let r = rect.standardized
        let points = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        return CloudAnnotation.make(points: points, color: color, lineWidth: lineWidth, fill: fill)
            ?? PDFAnnotation(bounds: r, forType: .square, withProperties: nil)
    }

    /// A scalloped revision cloud around an arbitrary polygon (page space); nil with fewer than three points.
    public static func cloudPolygon(points: [CGPoint], color: NSColor, lineWidth: CGFloat, fill: NSColor? = nil) -> PDFAnnotation? {
        CloudAnnotation.make(points: points, color: color, lineWidth: lineWidth, fill: fill)
    }
}
