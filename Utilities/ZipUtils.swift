import Foundation

struct ZipCentralDirectoryEntry {
    let isEncrypted: Bool
    let uncompressedSize: UInt32
    let fileName: String
}

struct ZipInspectionResult {
    let isZip: Bool
    let isMultiPart: Bool
    let entries: [ZipCentralDirectoryEntry]
    let totalUncompressedSize: UInt64
}

enum OverwritePolicy: String {
    case overwrite
    case skip
    case rename
}

enum ZipUtils {
    static func isZip(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "zip" || ext == "cbz" || ext == "z01" { return true }
        // Check signature
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let sig = try? fh.read(upToCount: 4)
        if sig == Data([0x50, 0x4b, 0x03, 0x04]) ||
            sig == Data([0x50, 0x4b, 0x05, 0x06]) ||
            sig == Data([0x50, 0x4b, 0x07, 0x08]) {
            return true
        }
        return false
    }

    static func collectMultipartSegments(for url: URL) -> (expected: [URL], found: [URL]) {
        // Strategy:
        // If url is .zip and there exists .z01 siblings, collect all zNN and .zip
        // If url is .z01, collect z01..zNN and .zip
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let baseName: String
        let ext = url.pathExtension.lowercased()
        if ext == "z01" {
            baseName = url.deletingPathExtension().lastPathComponent
        } else if ext == "zip" {
            baseName = url.deletingPathExtension().lastPathComponent
        } else {
            return (expected: [url], found: fm.fileExists(atPath: url.path) ? [url] : [])
        }
        var expected: [URL] = []
        var found: [URL] = []
        var idx = 1
        while true {
            let partExt = String(format: "z%02d", idx)
            let partURL = dir.appendingPathComponent("\(baseName).\(partExt)")
            if fm.fileExists(atPath: partURL.path) {
                expected.append(partURL)
                found.append(partURL)
                idx += 1
            } else {
                break
            }
        }
        // The last part should be .zip
        let last = dir.appendingPathComponent("\(baseName).zip")
        expected.append(last)
        if fm.fileExists(atPath: last.path) { found.append(last) }
        if expected.isEmpty { expected = [url] }
        if found.isEmpty, fm.fileExists(atPath: url.path) { found = [url] }
        return (expected, found)
    }

    static func isMultiPart(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "z01" { return true }
        let (expected, found) = collectMultipartSegments(for: url)
        return expected.count > 1 && found.count == expected.count
    }

    static func inspect(url: URL) throws -> ZipInspectionResult {
        let data = try Data(contentsOf: url)
        guard data.count >= 22 else {
            return ZipInspectionResult(isZip: false, isMultiPart: false, entries: [], totalUncompressedSize: 0)
        }
        let isSigZip = data.starts(with: Data([0x50, 0x4b]))
        // Find End of Central Directory record (EOCD) signature: 0x06054b50
        let eocdSig = Data([0x50, 0x4b, 0x05, 0x06])
        let searchLen = min(66_000, data.count)
        let searchStart = data.count - searchLen
        var eocdIndex: Int? = nil
        if searchStart >= 0 {
            let tail = data[searchStart..<data.count]
            if let range = tail.range(of: eocdSig) {
                eocdIndex = searchStart + range.lowerBound
            }
        }
        guard let eocd = eocdIndex else {
            return ZipInspectionResult(isZip: isSigZip, isMultiPart: false, entries: [], totalUncompressedSize: 0)
        }
        func readUInt16(_ offset: Int) -> UInt16 {
            let lo = UInt16(data[offset])
            let hi = UInt16(data[offset+1])
            return (hi << 8) | lo
        }
        func readUInt32(_ offset: Int) -> UInt32 {
            let b0 = UInt32(data[offset])
            let b1 = UInt32(data[offset+1])
            let b2 = UInt32(data[offset+2])
            let b3 = UInt32(data[offset+3])
            return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
        }
        let cdSize = Int(readUInt32(eocd + 12))
        let cdOffset = Int(readUInt32(eocd + 16))
        guard cdOffset + cdSize <= data.count else {
            return ZipInspectionResult(isZip: isSigZip, isMultiPart: false, entries: [], totalUncompressedSize: 0)
        }
        var entries: [ZipCentralDirectoryEntry] = []
        var cursor = cdOffset
        while cursor < cdOffset + cdSize {
            // Central directory file header signature: 0x02014b50
            if !(data[cursor..<(cursor+4)] == Data([0x50, 0x4b, 0x01, 0x02])) {
                break
            }
            let gpbf = readUInt16(cursor + 8)
            let method = readUInt16(cursor + 10)
            _ = method
            let uncompSize = readUInt32(cursor + 24)
            let fileNameLen = Int(readUInt16(cursor + 28))
            let extraLen = Int(readUInt16(cursor + 30))
            let commentLen = Int(readUInt16(cursor + 32))
            let nameData = data[(cursor + 46)..<(cursor + 46 + fileNameLen)]
            let fileName = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .ascii) ?? ""
            let isEncrypted = (gpbf & 0x0001) != 0
            entries.append(ZipCentralDirectoryEntry(isEncrypted: isEncrypted, uncompressedSize: uncompSize, fileName: fileName))
            cursor += 46 + fileNameLen + extraLen + commentLen
        }
        let totalSize = entries.reduce(0) { $0 + UInt64($1.uncompressedSize) }
        // Multi-part detection by spanning signature: Not robust here; use filename-based detection
        let isMulti = isMultiPart(url: url)
        return ZipInspectionResult(isZip: isSigZip, isMultiPart: isMulti, entries: entries, totalUncompressedSize: totalSize)
    }
}
