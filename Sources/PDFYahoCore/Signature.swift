import AppKit
import PDFKit

/// A hand-drawn signature: strokes normalised to a unit-height box with y pointing up.
public struct Signature: Codable, Equatable, Sendable {
    public var strokes: [[CGPoint]]
    public var aspectRatio: CGFloat

    /// Builds a signature from strokes captured in a y-down view of the given height.
    public init?(viewStrokes: [[CGPoint]], viewHeight: CGFloat) {
        let flipped = viewStrokes.filter { !$0.isEmpty }.map { $0.map { CGPoint(x: $0.x, y: viewHeight - $0.y) } }
        let all = flipped.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max()
        else { return nil }
        let height = max(maxY - minY, 1)
        strokes = flipped.map { $0.map { CGPoint(x: ($0.x - minX) / height, y: ($0.y - minY) / height) } }
        aspectRatio = max(maxX - minX, 1) / height
    }

    /// Ink annotation centred on `center`, `width` points wide.
    public func annotation(center: CGPoint, width: CGFloat, color: NSColor) -> PDFAnnotation? {
        let height = width / aspectRatio
        let origin = CGPoint(x: center.x - width / 2, y: center.y - height / 2)
        let placed = strokes.map { $0.map { CGPoint(x: origin.x + $0.x * height, y: origin.y + $0.y * height) } }
        return Annotations.ink(strokes: placed, color: color, lineWidth: 1.5)
    }
}

public enum SignatureStore {
    static let key = "org.pdfyaho.signature"

    public static func load(_ defaults: UserDefaults = .standard) -> Signature? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Signature.self, from: data)
    }

    public static func save(_ signature: Signature?, _ defaults: UserDefaults = .standard) {
        if let signature, let data = try? JSONEncoder().encode(signature) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
