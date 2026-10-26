#if PDFIUM
import AppKit
import CPDFium
import CoreText

/// A PDFium document loaded from memory. PDFium is not thread-safe, so use it from one thread at a time.
final class PDFiumDocument {
    let handle: FPDF_DOCUMENT
    private let buffer: UnsafeMutableRawPointer

    private static let library: Void = {
        var config = FPDF_LIBRARY_CONFIG()
        config.version = 2
        FPDF_InitLibraryWithConfig(&config)
    }()

    init?(data: Data, password: String? = nil) {
        _ = Self.library
        // PDFium reads lazily from the buffer, so it must outlive the document.
        buffer = .allocate(byteCount: max(data.count, 1), alignment: 1)
        data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
        guard let doc = FPDF_LoadMemDocument64(buffer, data.count, password) else {
            buffer.deallocate()
            return nil
        }
        handle = doc
    }

    init?() {
        _ = Self.library
        buffer = .allocate(byteCount: 1, alignment: 1)
        guard let doc = FPDF_CreateNewDocument() else { buffer.deallocate(); return nil }
        handle = doc
    }

    deinit {
        FPDF_CloseDocument(handle)
        buffer.deallocate()
    }

    var pageCount: Int { Int(FPDF_GetPageCount(handle)) }

    func withPage<T>(_ index: Int, _ body: (FPDF_PAGE) throws -> T) rethrows -> T? {
        guard let page = FPDF_LoadPage(handle, Int32(index)) else { return nil }
        defer { FPDF_ClosePage(page) }
        return try body(page)
    }

    func save() -> Data? {
        var bytes: UnsafeMutablePointer<UInt8>?
        var size = 0
        guard PCSaveDocument(handle, FPDF_DWORD(FPDF_NO_INCREMENTAL), &bytes, &size) != 0, let bytes else { return nil }
        defer { free(bytes) }
        return Data(bytes: bytes, count: size)
    }
}

/// A CGImage from a PDFium BGRA bitmap.
func cgImage(from bitmap: FPDF_BITMAP) -> CGImage? {
    let width = Int(FPDFBitmap_GetWidth(bitmap)), height = Int(FPDFBitmap_GetHeight(bitmap))
    let stride = Int(FPDFBitmap_GetStride(bitmap))
    guard width > 0, height > 0, let base = FPDFBitmap_GetBuffer(bitmap) else { return nil }
    let format = FPDFBitmap_GetFormat(bitmap)
    let data = Data(bytes: base, count: stride * height)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    let space = CGColorSpaceCreateDeviceRGB()
    switch Int32(format) {
    case FPDFBitmap_BGRA, FPDFBitmap_BGRx:
        let alpha: CGImageAlphaInfo = Int32(format) == FPDFBitmap_BGRA ? .premultipliedFirst : .noneSkipFirst
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    case FPDFBitmap_BGR:
        // Expand 24-bit BGR to 32-bit so CoreGraphics accepts it.
        var out = Data(count: width * height * 4)
        out.withUnsafeMutableBytes { dst in
            let d = dst.bindMemory(to: UInt8.self)
            let s = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let si = y * stride + x * 3, di = (y * width + x) * 4
                    d[di] = s[si]; d[di + 1] = s[si + 1]; d[di + 2] = s[si + 2]; d[di + 3] = 255
                }
            }
        }
        guard let p = CGDataProvider(data: out as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: p, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    case FPDFBitmap_Gray:
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: stride,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    default:
        return nil
    }
}

/// A PDFium BGRA bitmap holding `image`. The caller destroys it.
func bitmap(from image: CGImage) -> FPDF_BITMAP? {
    let width = image.width, height = image.height
    guard let bitmap = FPDFBitmap_Create(Int32(width), Int32(height), 1), let base = FPDFBitmap_GetBuffer(bitmap) else { return nil }
    let stride = Int(FPDFBitmap_GetStride(bitmap))
    guard let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { FPDFBitmap_Destroy(bitmap); return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bitmap
}
#endif
