import Foundation

// MARK: - 嗅探结果

enum StreamKind: String, Codable {
    case hls
    case file

    var displayName: String {
        switch self {
        case .hls: return "HLS"
        case .file: return "文件"
        }
    }
}

struct SniffedStream: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var url: URL
    var pageURL: URL?
    var pageTitle: String?
    var kind: StreamKind = .hls
    var discoveredAt: Date = Date()

    var displayTitle: String {
        if let title = pageTitle, !title.isEmpty { return title }
        return url.lastPathComponent.isEmpty ? url.host ?? "未知来源" : url.lastPathComponent
    }

    var hostText: String {
        guard let host = url.host else { return url.absoluteString }
        return host
    }
}

// MARK: - 清晰度选项

struct VariantOption: Identifiable, Hashable {
    let id: String
    let url: URL
    let label: String
    let detail: String

    init(variant: HLSVariant) {
        self.id = variant.url.absoluteString
        self.url = variant.url
        self.label = variant.resolution ?? "未知分辨率"
        var parts: [String] = []
        if let bandwidth = variant.bandwidth {
            parts.append(String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000))
        }
        if let frameRate = variant.frameRate {
            parts.append(String(format: "%.0f fps", frameRate))
        }
        if let codecs = variant.codecs {
            parts.append(codecs)
        }
        self.detail = parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

// MARK: - 输出格式

enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case mp4
    case ts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .ts: return "TS"
        }
    }

    var detail: String {
        switch self {
        case .mp4: return "合并后无损转封装为 MP4，可直接进相册 / 播放器"
        case .ts: return "只合并分片，保留原始 MPEG-TS，不做转封装"
        }
    }
}

// MARK: - 任务状态

enum DownloadPhase: String, Codable, Equatable {
    case queued
    case fetching
    case downloading
    case merging
    case finished
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .queued: return "排队中"
        case .fetching: return "解析列表"
        case .downloading: return "下载分片"
        case .merging: return "合并转换"
        case .finished: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .fetching, .downloading, .merging: return true
        default: return false
        }
    }
}

// MARK: - 错误

enum DownloadError: LocalizedError {
    case http(Int, String)
    case badPlaylist
    case emptyPlaylist
    case emptySegment(String)
    case badKey
    case sampleAES
    case cancelled
    case network(String)
    case remux(String)

    var errorDescription: String? {
        switch self {
        case let .http(code, url):
            return "HTTP \(code)：\(url)"
        case .badPlaylist:
            return "播放列表内容无法解析（不是合法的 m3u8）"
        case .emptyPlaylist:
            return "播放列表里没有任何分片"
        case let .emptySegment(url):
            return "分片返回空数据：\(url)"
        case .badKey:
            return "AES-128 密钥长度不正确（应为 16 字节）"
        case .sampleAES:
            return "该视频使用 SAMPLE-AES 加密，需要额外解密流程，暂不支持"
        case .cancelled:
            return "任务已取消"
        case let .network(message):
            return "网络错误：\(message)"
        case let .remux(message):
            return "转封装失败：\(message)"
        }
    }
}
