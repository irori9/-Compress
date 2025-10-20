import Foundation
import UniformTypeIdentifiers

public final class SecurityScopedBookmarkStore {
    public static let shared = SecurityScopedBookmarkStore()

    private let defaults = UserDefaults.standard
    private let recentsKey = "RecentDirectoryBookmarks"
    private let queue = DispatchQueue(label: "bookmark.store.queue")

    private init() {}

    // Save a security-scoped bookmark for a directory URL. Duplicates are de-duped by standardized fileURL path.
    public func addRecentDirectory(_ url: URL) {
        let dirURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard dirURL.isFileURL else { return }
        queue.sync {
            var list = (defaults.array(forKey: recentsKey) as? [Data]) ?? []
            // Create bookmark data
            guard let data = try? dirURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
            // Filter out any existing entry that resolves to same path
            var newList: [Data] = []
            var existingPaths = Set<String>()
            for b in list {
                if let resolved = resolveBookmark(b), let path = try? resolved.resourceValues(forKeys: [.isDirectoryKey]).url?.standardizedFileURL.path {
                    existingPaths.insert(path)
                    newList.append(b)
                }
            }
            let dirPath = dirURL.standardizedFileURL.path
            if !existingPaths.contains(dirPath) {
                newList.insert(data, at: 0)
            }
            // Keep at most 10
            if newList.count > 10 { newList = Array(newList.prefix(10)) }
            defaults.set(newList, forKey: recentsKey)
        }
    }

    public func listRecentDirectories() -> [URL] {
        let list = (defaults.array(forKey: recentsKey) as? [Data]) ?? []
        var urls: [URL] = []
        for data in list {
            if let url = resolveBookmark(data) { urls.append(url) }
        }
        return urls
    }

    // If a bookmark exists for a directory that contains the given URL, start accessing it.
    // Returns true if access was started.
    @discardableResult
    public func startAccessIfBookmarked(for url: URL) -> Bool {
        let list = (defaults.array(forKey: recentsKey) as? [Data]) ?? []
        let path = url.standardizedFileURL.path
        for data in list {
            if let dir = resolveBookmark(data) {
                let dirPath = dir.standardizedFileURL.path
                if path.hasPrefix(dirPath) {
                    _ = dir.startAccessingSecurityScopedResource()
                    return true
                }
            }
        }
        return false
    }

    public func clear() {
        defaults.removeObject(forKey: recentsKey)
    }

    // Resolve a bookmark and start security scope access immediately. The caller does not need to stop access.
    @discardableResult
    public func resolveAndStartAccessing(_ data: Data) -> URL? {
        guard let url = resolveBookmark(data) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    public func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                // Refresh stale bookmark
                let refreshed = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                var list = (defaults.array(forKey: recentsKey) as? [Data]) ?? []
                if let idx = list.firstIndex(of: data) {
                    list[idx] = refreshed
                    defaults.set(list, forKey: recentsKey)
                }
            }
            return url
        } catch {
            return nil
        }
    }
}

public enum SecurityScope {
    // Synchronous helper
    public static func access<T>(to url: URL, _ block: () throws -> T) rethrows -> T {
        let need = url.startAccessingSecurityScopedResource()
        defer { if need { url.stopAccessingSecurityScopedResource() } }
        return try block()
    }

    // Async helper
    public static func access<T>(to url: URL, _ block: () async throws -> T) async rethrows -> T {
        let need = url.startAccessingSecurityScopedResource()
        defer { if need { url.stopAccessingSecurityScopedResource() } }
        return try await block()
    }
}

public enum FileCoordination {
    public static func coordinateReadWrite(reading input: URL, writing outputDir: URL, _ block: (_ coordinatedInput: URL, _ coordinatedOutputDir: URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var readErr: NSError?
        var writeErr: NSError?
        coordinator.coordinate(readingItemAt: input, options: [], writingItemAt: outputDir, options: [.forMerging], error: &readErr) { readURL, writeURL in
            do {
                try block(readURL, writeURL)
            } catch {
                writeErr = error as NSError
            }
        }
        if let e = readErr { throw e }
        if let e = writeErr { throw e }
    }
}
