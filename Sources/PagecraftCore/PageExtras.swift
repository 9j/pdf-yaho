import AppKit
import PDFKit

public enum EnhanceMode: String, CaseIterable, Identifiable, Sendable {
    case blackAndWhite = "Black & White", grayscale = "Grayscale", color = "Color"
    public var id: String { rawValue }
}

extension PageOps {
    /// Resolution pages are rendered at when enhanced.
    public static let enhanceDPI: CGFloat = 200

    /// Cleans up a scanned page: whitens the paper, deepens the ink and optionally removes colour.
    ///
    /// - `.color`: per-channel white balance and contrast stretch, so tinted paper turns white.
    /// - `.grayscale`: the same, then converted to gray.
    /// - `.blackAndWhite`: gray, then an adaptive threshold, which copes with uneven lighting and shadows.
    ///
    /// The page is rendered at about 200 dpi and replaced by an image of the same size in points.
    /// **The result is a flat image: the text layer and vector content are lost** (run OCR again if you
    /// need searchable text). Annotations on the page are burnt into the image.
    public static func enhanced(_ page: PDFPage, mode: EnhanceMode) -> PDFPage? {
        let scale = enhanceDPI / 72
        let box = page.bounds(for: .cropBox)
        let shown = displaySize(page)
        let width = Int((shown.width * scale).rounded()), height = Int((shown.height * scale).rounded())
        guard width > 0, height > 0, box.width > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: CGFloat(width) / shown.width, y: CGFloat(height) / shown.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        page.draw(with: .cropBox, to: ctx)
        NSGraphicsContext.restoreGraphicsState()
        guard let pixels = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        let output: CGImage?
        switch mode {
        case .color:
            ImageCleanup.whiteBalance(pixels, width: width, height: height)
            output = ctx.makeImage()
        case .grayscale, .blackAndWhite:
            var gray = ImageCleanup.luminance(pixels, count: width * height)
            ImageCleanup.stretch(&gray)
            if mode == .blackAndWhite { ImageCleanup.adaptiveThreshold(&gray, width: width, height: height) }
            output = ImageCleanup.grayImage(gray, width: width, height: height)
        }
        guard let output else { return nil }
        return PDFPage(image: NSImage(cgImage: output, size: shown))
    }

    // MARK: Book spreads

    /// Splits a two-page spread (a scan of an open book) into its left and right halves, in reading order.
    ///
    /// The halves are copies of the page with the crop box narrowed, so text and vector content stay as they
    /// are. The page rotation is taken into account: the halves are what you see on screen, left and right.
    /// Annotations that lie entirely in the other half are dropped from each copy.
    public static func splitSpread(_ page: PDFPage) -> [PDFPage] {
        let crop = page.bounds(for: .cropBox)
        guard crop.width > 0, crop.height > 0 else { return [] }
        let leftOfPage = CGRect(x: crop.minX, y: crop.minY, width: crop.width / 2, height: crop.height)
        let rightOfPage = CGRect(x: crop.midX, y: crop.minY, width: crop.width / 2, height: crop.height)
        let bottomOfPage = CGRect(x: crop.minX, y: crop.minY, width: crop.width, height: crop.height / 2)
        let topOfPage = CGRect(x: crop.minX, y: crop.midY, width: crop.width, height: crop.height / 2)
        let displayed: [CGRect]
        switch ((page.rotation % 360) + 360) % 360 {
        case 90: displayed = [bottomOfPage, topOfPage]
        case 180: displayed = [rightOfPage, leftOfPage]
        case 270: displayed = [topOfPage, bottomOfPage]
        default: displayed = [leftOfPage, rightOfPage]
        }
        let halves = displayed.compactMap { rect -> PDFPage? in
            guard let copy = page.copy() as? PDFPage else { return nil }
            copy.setBounds(rect, for: .cropBox)
            for a in copy.annotations where !a.bounds.intersects(rect) { copy.removeAnnotation(a) }
            return copy
        }
        return halves.count == 2 ? halves : []
    }
}

extension PDFOps {
    /// Puts a PDF containing copies of `pages` on the pasteboard as `.pdf`, ready for `PageOps.pages(from:)`.
    @discardableResult
    public static func writePages(_ pages: [PDFPage], to pasteboard: NSPasteboard) -> Bool {
        guard !pages.isEmpty else { return false }
        let doc = PDFDocument()
        for (i, page) in copies(of: pages).enumerated() { doc.insert(page, at: i) }
        guard doc.pageCount == pages.count, let data = doc.dataRepresentation() else { return false }
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .pdf)
    }
}

/// Pixel-level helpers for scan enhancement.
enum ImageCleanup {
    /// Value at the given fraction of the histogram, 0...1.
    private static func percentile(_ histogram: [Int], total: Int, _ fraction: Double) -> Int {
        let target = Int(Double(total) * fraction)
        var sum = 0
        for (value, count) in histogram.enumerated() {
            sum += count
            if sum > target { return value }
        }
        return 255
    }

    /// Black and white points that map ink to black and paper to white. The white point is the paper level
    /// (a high percentile, never below mid gray so photos are not blown out).
    private static func levels(_ histogram: [Int], total: Int) -> (black: Int, white: Int) {
        let black = min(percentile(histogram, total: total, 0.001), 100)
        let white = max(percentile(histogram, total: total, 0.9), 150)
        return (black, max(white, black + 20))
    }

    private static func lookup(black: Int, white: Int) -> [UInt8] {
        (0..<256).map { v in UInt8(max(0, min(255, (Double(v - black) / Double(white - black)) * 255))) }
    }

    /// Stretches RGBA pixels per channel so the paper becomes white and the ink darker.
    static func whiteBalance(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int) {
        let count = width * height
        var counts = [Int](repeating: 0, count: 256 * 3)
        counts.withUnsafeMutableBufferPointer { h in
            for i in 0..<count {
                h[Int(pixels[i * 4])] += 1
                h[256 + Int(pixels[i * 4 + 1])] += 1
                h[512 + Int(pixels[i * 4 + 2])] += 1
            }
        }
        // White points are per channel, which removes paper tints.
        let tables = (0..<3).map { c -> [UInt8] in
            let l = levels(Array(counts[(c * 256)..<((c + 1) * 256)]), total: count)
            return lookup(black: l.black, white: l.white)
        }
        tables[0].withUnsafeBufferPointer { r in tables[1].withUnsafeBufferPointer { g in tables[2].withUnsafeBufferPointer { b in
            for i in 0..<count {
                pixels[i * 4] = r[Int(pixels[i * 4])]
                pixels[i * 4 + 1] = g[Int(pixels[i * 4 + 1])]
                pixels[i * 4 + 2] = b[Int(pixels[i * 4 + 2])]
            }
        } } }
    }

    static func luminance(_ pixels: UnsafeMutablePointer<UInt8>, count: Int) -> [UInt8] {
        var gray = [UInt8](repeating: 0, count: count)
        gray.withUnsafeMutableBufferPointer { out in
            for i in 0..<count {
                let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
                out[i] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
            }
        }
        return gray
    }

    static func stretch(_ gray: inout [UInt8]) {
        var histogram = [Int](repeating: 0, count: 256)
        let total = gray.count
        gray.withUnsafeMutableBufferPointer { px in
            histogram.withUnsafeMutableBufferPointer { h in for i in 0..<total { h[Int(px[i])] += 1 } }
            let l = levels(histogram, total: total)
            let table = lookup(black: l.black, white: l.white)
            table.withUnsafeBufferPointer { t in for i in 0..<total { px[i] = t[Int(px[i])] } }
        }
    }

    /// Black where a pixel is clearly darker than its neighbourhood (or simply very dark), white elsewhere.
    static func adaptiveThreshold(_ gray: inout [UInt8], width: Int, height: Int) {
        let stride = width + 1
        var integral = [Int](repeating: 0, count: stride * (height + 1))
        let radius = max(8, max(width, height) / 40)
        var out = gray
        integral.withUnsafeMutableBufferPointer { sums in
            gray.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    for y in 0..<height {
                        var row = 0
                        for x in 0..<width {
                            row += Int(src[y * width + x])
                            sums[(y + 1) * stride + x + 1] = sums[y * stride + x + 1] + row
                        }
                    }
                    for y in 0..<height {
                        let y0 = max(0, y - radius), y1 = min(height, y + radius + 1)
                        for x in 0..<width {
                            let x0 = max(0, x - radius), x1 = min(width, x + radius + 1)
                            let sum = sums[y1 * stride + x1] - sums[y0 * stride + x1] - sums[y1 * stride + x0] + sums[y0 * stride + x0]
                            let mean = sum / ((x1 - x0) * (y1 - y0))
                            let v = Int(src[y * width + x])
                            dst[y * width + x] = (v < 60 || v * 100 < mean * 82) ? 0 : 255
                        }
                    }
                }
            }
        }
        gray = out
    }

    static func grayImage(_ gray: [UInt8], width: Int, height: Int) -> CGImage? {
        var data = gray
        return data.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
    }
}
