import Foundation

struct RarInspectionResult {
    let isRar: Bool
    let isMultiPart: Bool
    let hasEncryptedEntries: Bool
}

enum RarUtils {
    static func isRar(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "rar" { return true }
        if ext.hasPrefix("r"), ext.count == 3, Int(ext.suffix(2)) != nil { return true } // .r00 style
        if url.lastPathComponent.lowercased().contains(".part") && url.pathExtension.lowercased() == "rar" { return true }
        // Signature check
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        guard let sig = try? fh.read(upToCount: 8) else { return false }
        // RAR 4.x is 7-byte signature
        let rar4 = Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00])
        if sig.count >= 7 && sig.prefix(7) == rar4 { return true }
        // RAR 5.x is 8-byte signature
        let rar5 = Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00])
        if sig.count >= 8 && sig.prefix(8) == rar5 { return true }
        return false
    }

    static func collectMultipartSegments(for url: URL) -> (expected: [URL], found: [URL]) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let lower = name.lowercased()
        // Case 1: name.partN.rar or name.partNN.rar
        if let range = lower.range(of: ".part"), lower.hasSuffix(".rar") {
            let base = String(lower[..<range.lowerBound])
            // Extract N
            let numStrStart = lower.index(range.upperBound, offsetBy: 0)
            let numStrEnd = lower.index(lower.endIndex, offsetBy: -4)
            let numStr = String(lower[numStrStart..<numStrEnd]).filter { $0.isNumber }
            let startIndex = (Int(numStr) ?? 1)
            var idx = startIndex
            var expected: [URL] = []
            var found: [URL] = []
            while true {
                let partName = String(format: "%@.part%02d.rar", base, idx)
                let partURL = dir.appendingPathComponent(partName)
                expected.append(partURL)
                if fm.fileExists(atPath: partURL.path) { found.append(partURL) }
                else { break }
                idx += 1
            }
            return (expected, found)
        }
        // Case 2: .r00 split with .rar
        let baseName: String
        let ext = url.pathExtension.lowercased()
        if ext == "rar" || (ext.hasPrefix("r") && ext.count == 3) {
            baseName = url.deletingPathExtension().lastPathComponent
        } else {
            return (expected: [url], found: fm.fileExists(atPath: url.path) ? [url] : [])
        }
        var expected: [URL] = []
        var found: [URL] = []
        var idx = 0
        while true {
            let partExt = String(format: "r%02d", idx)
            let partURL = dir.appendingPathComponent("\(baseName).\(partExt)")
            if fm.fileExists(atPath: partURL.path) {
                expected.append(partURL)
                found.append(partURL)
                idx += 1
            } else {
                break
            }
        }
        // The last part should be .rar
        let last = dir.appendingPathComponent("\(baseName).rar")
        expected.append(last)
        if fm.fileExists(atPath: last.path) { found.append(last) }
        if expected.isEmpty { expected = [url] }
        if found.isEmpty, fm.fileExists(atPath: url.path) { found = [url] }
        return (expected, found)
    }

    static func isMultiPart(url: URL) -> Bool {
        let (expected, found) = collectMultipartSegments(for: url)
        return expected.count > 1 && found.count == expected.count
    }
}
