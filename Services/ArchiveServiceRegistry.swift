import Foundation

public actor ArchiveServiceRegistry {
    public static let shared = ArchiveServiceRegistry()

    private var services: [ArchiveService] = [
        ZipArchiveService(),
        RarArchiveService(),
        SevenZArchiveService()
    ]

    public func service(for format: ArchiveFormat) -> ArchiveService? {
        services.first { $0.supportedFormats.contains(format) }
    }

    public func probe(inputURL: URL) async -> ArchiveFormat {
        let ext = inputURL.pathExtension.lowercased()
        switch ext {
        case "zip": return .zip
        case "rar": return .rar
        case "7z": return .sevenZ
        default:
            for s in services {
                if let f = await s.probe(inputURL: inputURL) { return f }
            }
            return .auto
        }
    }
}
