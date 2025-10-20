import Foundation
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

// A reusable handler that can be used by an Action/Share Extension target to provide
// "解压到此处" for ZIP/RAR/7Z archives and report progress via NSExtensionContext.progress.
public final class UnarchiveExtensionHandler {
    public init() {}

    // Supported UTTypes including multipart extensions (handled by services heuristics)
    private let supportedTypes: [UTType] = {
        var types: [UTType] = [.zip]
        let exts = ["z01", "rar", "r00", "7z", "001"]
        for e in exts {
            if let t = UTType(filenameExtension: e) { types.append(t) }
        }
        return types
    }()

    public func handle(context: NSExtensionContext) {
        let providers: [NSItemProvider] = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        guard !providers.isEmpty else {
            context.cancelRequest(withError: ArchiveError.unsupported("无可用附件").asNSError())
            return
        }

        let progress = Progress(totalUnitCount: 100)
        context.progress = progress

        // Process first matching provider
        guard let provider = providers.first(where: { p in
            supportedTypes.contains(where: { p.hasItemConformingToTypeIdentifier($0.identifier) })
        }) else {
            context.cancelRequest(withError: ArchiveError.unsupported("不支持的类型").asNSError())
            return
        }

        // Load file url from provider
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
            guard let self else { return }
            if let error = error {
                context.cancelRequest(withError: ArchiveError.ioError(error.localizedDescription).asNSError())
                return
            }
            var fileURL: URL?
            if let url = item as? URL { fileURL = url }
            else if let data = item as? Data, let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? { fileURL = url }
            guard let srcURL = fileURL else {
                context.cancelRequest(withError: ArchiveError.unsupported("无法解析文件URL").asNSError())
                return
            }

            // Default destination: same directory as source, folder named after archive
            let destDir = srcURL.deletingPathExtension().deletingLastPathComponent()
                .appendingPathComponent(srcURL.deletingPathExtension().lastPathComponent, isDirectory: true)

            SecurityScopedBookmarkStore.shared.addRecentDirectory(srcURL)
            _ = SecurityScopedBookmarkStore.shared.startAccessIfBookmarked(for: srcURL)
            _ = SecurityScopedBookmarkStore.shared.startAccessIfBookmarked(for: destDir)

            Task { @MainActor in
                let format = await ArchiveServiceRegistry.shared.probe(inputURL: srcURL)
                guard let service = await ArchiveServiceRegistry.shared.service(for: format) else {
                    context.cancelRequest(withError: ArchiveError.unsupported("无法找到服务").asNSError())
                    return
                }
                do {
                    try await service.extract(
                        inputURL: srcURL,
                        destination: destDir,
                        password: nil,
                        progress: { p in
                            let fraction = max(0, min(1, p.fractionCompleted))
                            progress.completedUnitCount = Int64(fraction * 100)
                        },
                        cancellationToken: nil
                    )
                    context.completeRequest(returningItems: context.inputItems, completionHandler: nil)
                } catch let err as ArchiveError {
                    // Present a simple alert in extension host if possible, otherwise fail with error
                    context.cancelRequest(withError: err.asNSError())
                } catch {
                    context.cancelRequest(withError: ArchiveError.ioError(error.localizedDescription).asNSError())
                }
            }
        }
    }
}

private extension ArchiveError {
    func asNSError() -> NSError {
        NSError(domain: "ArchiveManager", code: 1, userInfo: [NSLocalizedDescriptionKey: self.errorDescription ?? "未知错误"])    }
}
#endif
