import Compression
import Foundation

/// A minimal ZIP archive writer: deflate when it helps, stored otherwise, no ZIP64.
public struct ZipWriter {
    private struct Entry {
        var name: [UInt8]
        var crc: UInt32
        var method: UInt16
        var compressedSize: UInt32
        var size: UInt32
        var offset: UInt32
    }

    private var body = Data()
    private var entries: [Entry] = []

    /// 1 January 2026, so the same input always gives the same archive.
    private static let dosDate: UInt16 = (2026 - 1980) << 9 | 1 << 5 | 1

    public init() {}

    public mutating func add(path: String, data: Data) {
        let name = Array(path.utf8)
        let crc = Self.crc32(data)
        var method: UInt16 = 0
        var payload = data
        if data.count > 64, let packed = Self.deflate(data), packed.count < data.count {
            method = 8
            payload = packed
        }
        let entry = Entry(name: name, crc: crc, method: method, compressedSize: UInt32(payload.count),
                          size: UInt32(data.count), offset: UInt32(body.count))
        body.append(UInt32(0x04034b50))
        body.append(UInt16(20))
        body.append(UInt16(0x0800))
        body.append(method)
        body.append(UInt16(0))
        body.append(Self.dosDate)
        body.append(crc)
        body.append(entry.compressedSize)
        body.append(entry.size)
        body.append(UInt16(name.count))
        body.append(UInt16(0))
        body.append(contentsOf: name)
        body.append(payload)
        entries.append(entry)
    }

    /// The finished archive.
    public var data: Data {
        var out = body
        let directoryStart = out.count
        for e in entries {
            out.append(UInt32(0x02014b50))
            out.append(UInt16(20))
            out.append(UInt16(20))
            out.append(UInt16(0x0800))
            out.append(e.method)
            out.append(UInt16(0))
            out.append(Self.dosDate)
            out.append(e.crc)
            out.append(e.compressedSize)
            out.append(e.size)
            out.append(UInt16(e.name.count))
            out.append(UInt16(0))
            out.append(UInt16(0))
            out.append(UInt16(0))
            out.append(UInt16(0))
            out.append(UInt32(0))
            out.append(e.offset)
            out.append(contentsOf: e.name)
        }
        let directorySize = out.count - directoryStart
        out.append(UInt32(0x06054b50))
        out.append(UInt16(0))
        out.append(UInt16(0))
        out.append(UInt16(entries.count))
        out.append(UInt16(entries.count))
        out.append(UInt32(directorySize))
        out.append(UInt32(directoryStart))
        out.append(UInt16(0))
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return ~crc
    }

    /// Raw deflate, which is what Compression's zlib algorithm emits and what ZIP stores.
    private static func deflate(_ data: Data) -> Data? {
        let capacity = data.count + 1024
        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { out.deallocate() }
        let written = data.withUnsafeBytes { src -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(out, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return written > 0 ? Data(bytes: out, count: written) : nil
    }
}

private extension Data {
    mutating func append(_ value: UInt16) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append(_ value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
}
