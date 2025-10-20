import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = Self.supportedContentTypes
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        controller.allowsMultipleSelection = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    // Supported archive UTTypes and common split-volume extensions
    private static var supportedContentTypes: [UTType] {
        var set = Set<UTType>()
        set.insert(.zip)
        ["cbz", "rar", "7z"].forEach { ext in
            if let t = UTType(filenameExtension: ext) { set.insert(t) }
        }
        // ZIP split parts: .z01 ... .z99
        for i in 1...99 {
            let ext = String(format: "z%02d", i)
            if let t = UTType(filenameExtension: ext) { set.insert(t) }
        }
        // RAR split parts: .r00 ... .r99
        for i in 0...99 {
            let ext = String(format: "r%02d", i)
            if let t = UTType(filenameExtension: ext) { set.insert(t) }
        }
        // Generic numeric parts: .001 ... .099
        for i in 1...99 {
            let ext = String(format: "%03d", i)
            if let t = UTType(filenameExtension: ext) { set.insert(t) }
        }
        return Array(set)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Task { [weak self] in
                await self?.importAndReturn(urls: urls, presenter: controller)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}

        // MARK: - Import logic
        private func importAndReturn(urls: [URL], presenter: UIViewController) async {
            let fm = FileManager.default
            let importsDir = Self.importsDirectory()
            do { try fm.createDirectory(at: importsDir, withIntermediateDirectories: true) } catch {}

            var resultTaskURLs: [URL] = []
            var processedGroups = Set<String>()

            for originalURL in urls {
                let need = originalURL.startAccessingSecurityScopedResource()
                defer { if need { originalURL.stopAccessingSecurityScopedResource() } }
                do {
                    guard let (format, style, foundSegments) = try determineFormatAndSegments(for: originalURL) else {
                        continue
                    }
                    let groupKey = makeGroupKey(for: originalURL, format: format, style: style)
                    if processedGroups.contains(groupKey) { continue }

                    // Compute root base for the group
                    let rootBase = computeRootBase(for: originalURL, format: format, style: style)

                    // Compute a collision-free root base in Imports/DATE directory (apply -1, -2 ...)
                    let resolvedRootBase = nextAvailableRootBase(rootBase, style: style, in: importsDir, for: foundSegments)

                    // Copy all found segments with coordinated access
                    var destURLs: [URL] = []
                    for seg in foundSegments {
                        do {
                            let destName = destinationFileName(for: seg, rootBase: resolvedRootBase, format: format, style: style)
                            let destURL = importsDir.appendingPathComponent(destName)
                            try copyItemCoordinated(from: seg, to: destURL)
                            destURLs.append(destURL)
                        } catch {
                            // Bubble up to show alert
                            throw error
                        }
                    }

                    // Determine the primary file URL to enqueue (controller file for multipart)
                    if let primary = primaryURL(in: destURLs, rootBase: resolvedRootBase, format: format, style: style) {
                        resultTaskURLs.append(primary)
                    } else if let single = destURLs.first {
                        resultTaskURLs.append(single)
                    }

                    processedGroups.insert(groupKey)
                } catch {
                    await presentError(error, presenter: presenter) { [weak self] in
                        Task { await self?.importAndReturn(urls: urls, presenter: presenter) }
                    }
                    return
                }
            }

            if !resultTaskURLs.isEmpty {
                onPick(resultTaskURLs)
            }
        }

        // MARK: - Helpers
        private static func importsDirectory() -> URL {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd"
            let folder = dateFmt.string(from: Date())
            let base = docs.appendingPathComponent("Imports", isDirectory: true).appendingPathComponent(folder, isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        }

        private func determineFormatAndSegments(for url: URL) throws -> (ArchiveFormat, GroupStyle, [URL])? {
            let lower = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            if ZipUtils.isZip(url: url) {
                let (expected, found) = ZipUtils.collectMultipartSegments(for: url)
                let style: GroupStyle = (ext.hasPrefix("z") && ext.count == 3) ? .zipMulti : (expected.count > 1 ? .zipMulti : .single)
                return (.zip, style, found)
            } else if RarUtils.isRar(url: url) {
                let (expected, found) = RarUtils.collectMultipartSegments(for: url)
                let style: GroupStyle
                if lower.contains(".part") && lower.hasSuffix(".rar") { style = .rarPart }
                else if (ext.hasPrefix("r") && ext.count == 3 && Int(ext.suffix(2)) != nil) || expected.count > 1 { style = .rarRnn }
                else { style = .single }
                return (.rar, style, found)
            } else if SevenZUtils.is7z(url: url) {
                let (expected, found) = SevenZUtils.collectMultipartSegments(for: url)
                let style: GroupStyle
                if lower.contains(".7z.") { style = .sevenZDotParts }
                else if ext == "001" || expected.count > 1 { style = .sevenZNumeric }
                else { style = .single }
                return (.sevenZ, style, found)
            }
            return nil
        }

        private enum GroupStyle { case single, zipMulti, rarRnn, rarPart, sevenZDotParts, sevenZNumeric }

        private func makeGroupKey(for url: URL, format: ArchiveFormat, style: GroupStyle) -> String {
            let dir = url.deletingLastPathComponent().standardizedFileURL.path
            let root = computeRootBase(for: url, format: format, style: style)
            return "\(dir)|\(format.rawValue)|\(root)"
        }

        private func computeRootBase(for url: URL, format: ArchiveFormat, style: GroupStyle) -> String {
            let name = url.lastPathComponent
            let lower = name.lowercased()
            switch (format, style) {
            case (.rar, .rarPart):
                if let range = lower.range(of: ".part") {
                    let base = String(name[..<range.lowerBound])
                    return base
                }
                fallthrough
            default:
                // Default root base is name without its extension
                return url.deletingPathExtension().lastPathComponent
            }
        }

        private func nextAvailableRootBase(_ rootBase: String, style: GroupStyle, in dir: URL, for segments: [URL]) -> String {
            // If any of the destination file names already exists, append -1, -2 ... to the root base for the whole group
            let fm = FileManager.default
            var attempt = 0
            while true {
                let base = attempt == 0 ? rootBase : "\(rootBase)-\(attempt)"
                let conflict = segments.contains { seg in
                    let ext = seg.pathExtension
                    let name = destinationFileName(for: seg, rootBase: base, format: guessFormatForSegment(seg), style: style)
                    let path = dir.appendingPathComponent(name).path
                    return fm.fileExists(atPath: path)
                }
                if !conflict { return base }
                attempt += 1
            }
        }

        private func guessFormatForSegment(_ url: URL) -> ArchiveFormat {
            let ext = url.pathExtension.lowercased()
            if ext == "zip" || ext.hasPrefix("z") { return .zip }
            if ext == "rar" || (ext.hasPrefix("r") && ext.count == 3) { return .rar }
            if ext == "7z" || Int(ext) != nil { return .sevenZ }
            return .auto
        }

        private func destinationFileName(for sourceSegment: URL, rootBase: String, format: ArchiveFormat, style: GroupStyle) -> String {
            let name = sourceSegment.lastPathComponent
            let lower = name.lowercased()
            let ext = sourceSegment.pathExtension
            switch (format, style) {
            case (.zip, .zipMulti):
                // Preserve part extension: .z01/.z02 or .zip
                return "\(rootBase).\(ext)"
            case (.rar, .rarRnn):
                return "\(rootBase).\(ext)" // .rNN or .rar
            case (.rar, .rarPart):
                // name like foo.partNN.rar -> preserve NN
                if let r = lower.range(of: ".part"), lower.hasSuffix(".rar") {
                    let num = lower[r.upperBound...].dropLast(4) // strip .rar
                    return "\(rootBase).part\(num).rar"
                }
                return "\(rootBase).rar"
            case (.sevenZ, .sevenZDotParts):
                // name like foo.7z.001 -> preserve 001
                if let range = lower.range(of: ".7z.") {
                    let num = lower[range.upperBound...]
                    return "\(rootBase).7z.\(num)"
                }
                return "\(rootBase).7z"
            case (.sevenZ, .sevenZNumeric):
                // name like foo.001
                return "\(rootBase).\(ext)"
            default:
                return name // single: keep original name
            }
        }

        private func primaryURL(in destURLs: [URL], rootBase: String, format: ArchiveFormat, style: GroupStyle) -> URL? {
            switch (format, style) {
            case (.zip, .zipMulti):
                return destURLs.first { $0.lastPathComponent.lowercased().hasSuffix(".zip") } ?? destURLs.first
            case (.rar, .rarRnn):
                return destURLs.first { $0.pathExtension.lowercased() == "rar" } ?? destURLs.first
            case (.rar, .rarPart):
                // Prefer part01 if exists, else the lowest part
                let parts = destURLs.filter { $0.lastPathComponent.lowercased().contains(".part") && $0.pathExtension.lowercased() == "rar" }
                if let p01 = parts.first(where: { $0.lastPathComponent.lowercased().contains(".part01.") || $0.lastPathComponent.lowercased().contains(".part1.") }) {
                    return p01
                }
                return parts.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first ?? destURLs.first
            case (.sevenZ, .sevenZDotParts):
                return destURLs.first { $0.lastPathComponent.lowercased().contains(".7z.001") } ?? destURLs.first
            case (.sevenZ, .sevenZNumeric):
                // Prefer .001
                return destURLs.first { $0.pathExtension == "001" } ?? destURLs.first
            default:
                return destURLs.first
            }
        }

        private func copyItemCoordinated(from src: URL, to dst: URL) throws {
            let fm = FileManager.default
            try? fm.removeItem(at: dst) // ensure overwrite if exists (should be prevented by naming, but safe)
            try FileCoordination.coordinateReadWrite(reading: src, writing: dst.deletingLastPathComponent()) { readURL, writeDir in
                try fm.copyItem(at: readURL, to: dst)
            }
        }

        private func presentError(_ error: Error, presenter: UIViewController, retry: @escaping () -> Void) async {
            await MainActor.run {
                let alert = UIAlertController(title: "导入失败", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "重试", style: .default, handler: { _ in retry() }))
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                presenter.present(alert, animated: true)
            }
        }
    }
}
