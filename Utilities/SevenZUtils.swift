import Foundation

struct SevenZInspectionResult {
    let isSevenZ: Bool
    let isMultiPart: Bool
    let hasEncryptedEntries: Bool
}

enum SevenZUtils {
    static func is7z(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "7z" || ext == "001" || ext == "002" { return true }
        // Signature check for 7z: 37 7A BC AF 27 1C
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let sig = try? fh.read(upToCount: 6)
        if sig == Data([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) { return true }
        return false
    }

    static func collectMultipartSegments(for url: URL) -> (expected: [URL], found: [URL]) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let lower = name.lowercased()
        // Typical pattern: name.7z.001, .002 ...
        if lower.contains(".7z.") {
            let base = lower.components(separatedBy: ".7z.").first ?? lower
            var idx = 1
            var expected: [URL] = []
            var found: [URL] = []
            while true {
                let partName = String(format: "%@.7z.%03d", base, idx)
                let partURL = dir.appendingPathComponent(partName)
                expected.append(partURL)
                if fm.fileExists(atPath: partURL.path) { found.append(partURL) } else { break }
                idx += 1
            }
            return (expected, found)
        }
        // If opened with .001, assume it's 7z multi-part with any base
        if lower.hasSuffix(".001") {
            let base = String(lower.dropLast(4)) // remove .001
            var idx = 1
            var expected: [URL] = []
            var found: [URL] = []
            while true {
                let partName = String(format: "%@.%03d", base, idx)
                let partURL = dir.appendingPathComponent(partName)
                expected.append(partURL)
                if fm.fileExists(atPath: partURL.path) { found.append(partURL) } else { break }
                idx += 1
            }
            return (expected, found)
        }
        // Single part
        return (expected: [url], found: fm.fileExists(atPath: url.path) ? [url] : [])
    }

    static func isMultiPart(url: URL) -> Bool {
        let (expected, found) = collectMultipartSegments(for: url)
        return expected.count > 1 && found.count == expected.count
    }
}
