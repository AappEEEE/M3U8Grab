import Foundation
import UIKit

enum Paths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var downloads: URL {
        let url = documents.appendingPathComponent("Downloads", isDirectory: true)
        createIfNeeded(url)
        return url
    }

    static var workspaces: URL {
        let url = documents.appendingPathComponent("Workspaces", isDirectory: true)
        createIfNeeded(url)
        return url
    }

    static func createIfNeeded(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

func sanitizeFileName(_ raw: String) -> String {
    let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
    let cleaned = raw.components(separatedBy: illegal).joined(separator: "_")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let clipped = String(cleaned.prefix(70))
    return clipped.isEmpty ? "video" : clipped
}

func uniqueFileURL(directory: URL, baseName: String, pathExtension: String) -> URL {
    let safe = sanitizeFileName(baseName)
    var candidate = directory.appendingPathComponent("\(safe).\(pathExtension)")
    var counter = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
        candidate = directory.appendingPathComponent("\(safe)-\(counter).\(pathExtension)")
        counter += 1
    }
    return candidate
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useMB, .useGB, .useKB]
    return formatter.string(fromByteCount: bytes)
}

func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
}

func copyToPasteboard(_ text: String) {
    UIPasteboard.general.string = text
}

/// 在「文件」App 里打开本 App 的目录（shareddocuments: 是系统内部 scheme，
/// 失效时退回打开本 App 的设置页，至少不会白点）
func openFolderInFiles(_ folder: URL) {
    let path = folder.path
    if let url = URL(string: "shareddocuments://\(path)"), UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return
    }
    if let settings = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(settings, options: [:], completionHandler: nil)
    }
}


extension FileManager {
    func fileSize(at url: URL) -> Int64 {
        let attributes = try? attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

extension URL {
    var queryValue: [String: String] {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return [:] }
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { result[item.name] = value }
        }
        return result
    }
}
