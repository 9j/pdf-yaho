import CoreGraphics
import Foundation

/// Pure geometry helpers for drawing tools.
public enum Geometry {
    public enum ConstraintKind: Sendable {
        /// Lines and arrows: the angle snaps to a multiple of 45 degrees, the length is kept.
        case line
        /// Rectangles and ovals: width equals height, in the direction of the drag.
        case box
    }

    /// The end point of a drag from `start` to `end` with Shift held.
    public static func constrained(from start: CGPoint, to end: CGPoint, kind: ConstraintKind) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        switch kind {
        case .line:
            let length = hypot(dx, dy)
            guard length > 0 else { return end }
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            // Exact values on the axes and diagonals, free of floating point dust.
            let ux = (cos(angle) * 1e12).rounded() / 1e12, uy = (sin(angle) * 1e12).rounded() / 1e12
            return CGPoint(x: start.x + ux * length, y: start.y + uy * length)
        case .box:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
    }
}
