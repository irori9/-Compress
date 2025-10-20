import Foundation

public enum ArchiveFormat: String, CaseIterable, Codable, Sendable {
    case zip
    case rar
    case sevenZ
    case auto
}
