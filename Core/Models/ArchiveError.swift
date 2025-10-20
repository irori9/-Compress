import Foundation

public enum ArchiveError: LocalizedError, Sendable, Equatable {
    case passwordRequired
    case badPassword
    case missingVolumes(expected: [URL], found: [URL])
    case corrupted(String)
    case cancelled
    case ioError(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "需要密码才能解压此文件"
        case .badPassword:
            return "密码错误，请重试"
        case .missingVolumes(let expected, let found):
            let expectedNames = expected.map { $0.lastPathComponent }.joined(separator: ", ")
            let foundNames = found.map { $0.lastPathComponent }.joined(separator: ", ")
            return "分卷缺失。应包含: [\(expectedNames)]，实际找到: [\(foundNames)]"
        case .corrupted(let msg):
            return "压缩文件损坏：\(msg)"
        case .cancelled:
            return "已取消"
        case .ioError(let msg):
            return "读写错误：\(msg)"
        case .unsupported(let msg):
            return "暂不支持：\(msg)"
        }
    }
}

public extension ArchiveError {
    func asNSError() -> NSError {
        NSError(domain: "ArchiveManager", code: 1, userInfo: [NSLocalizedDescriptionKey: self.errorDescription ?? "未知错误"])
    }
}
