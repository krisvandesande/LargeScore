import Foundation
import Compression

/// Reads the files in a ZIP archive, enough for compressed MusicXML (.mxl): entries
/// stored or deflated, found through the central directory.
nonisolated enum ZipReader {
    enum Failure: Error { case notZip, unsupported, damaged }

    struct Entry {
        var name: String
        var method: UInt16
        var compressedSize: Int
        var size: Int
        var localHeaderOffset: Int
    }

    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        // The end-of-central-directory record sits in the last 64 KB + 22 bytes.
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard bytes.count >= 22 else { throw Failure.notZip }
        var end = -1
        var i = bytes.count - 22
        let floor = max(0, bytes.count - 22 - 65_535)
        while i >= floor {
            if Array(bytes[i..<i + 4]) == signature { end = i; break }
            i -= 1
        }
        guard end >= 0 else { throw Failure.notZip }
        let count = Int(u16(bytes, end + 10))
        var offset = Int(u32(bytes, end + 16))
        var result: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(bytes, offset) == 0x0201_4B50 else { throw Failure.damaged }
            let method = u16(bytes, offset + 10)
            let compressed = Int(u32(bytes, offset + 20))
            let size = Int(u32(bytes, offset + 24))
            let nameLength = Int(u16(bytes, offset + 28))
            let extraLength = Int(u16(bytes, offset + 30))
            let commentLength = Int(u16(bytes, offset + 32))
            let local = Int(u32(bytes, offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw Failure.damaged }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            result.append(Entry(name: name, method: method, compressedSize: compressed, size: size, localHeaderOffset: local))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    static func contents(of entry: Entry, in data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let o = entry.localHeaderOffset
        guard o + 30 <= bytes.count, u32(bytes, o) == 0x0403_4B50 else { throw Failure.damaged }
        let start = o + 30 + Int(u16(bytes, o + 26)) + Int(u16(bytes, o + 28))
        guard start + entry.compressedSize <= bytes.count else { throw Failure.damaged }
        let raw = Array(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0:
            return Data(raw)
        case 8:
            return try inflate(raw, size: entry.size)
        default:
            throw Failure.unsupported
        }
    }

    /// Raw deflate, as ZIP stores it; Apple's ZLIB algorithm reads exactly that.
    private static func inflate(_ input: [UInt8], size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(destination.baseAddress!, size, source.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.damaged }
        return Data(output)
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}
