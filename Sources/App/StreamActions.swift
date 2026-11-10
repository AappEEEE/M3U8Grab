import Foundation

/// 嗅探列表与浏览器悬浮球共用的“一键下载”逻辑。
/// 只做解析与入队，UI 反馈通过返回值交给调用方。
enum StreamActions {
    enum Outcome {
        case queued(segments: Int)
        case failed(String)
        case unsupported(String)

        var message: String {
            switch self {
            case .queued(let segments): return "已加入下载 · \(segments) 个分片"
            case .failed(let text): return "加入失败：\(text)"
            case .unsupported(let text): return text
            }
        }
    }

    /// 解析播放列表（master 自动选最高码率），并创建一个下载任务。
    @MainActor
    static func quickDownload(_ stream: SniffedStream, sniffer: Sniffer, store: DownloadStore) async -> Outcome {
        guard stream.kind == .hls else {
            return .unsupported(unsupportedReason(for: stream))
        }
        let referer = sniffer.referer(for: stream)
        do {
            let text = try await HLSClient.getText(url: stream.url, referer: referer)
            var playlist = try HLSParser.parse(text: text, url: stream.url)
            var target: URL?
            if playlist.isMaster {
                guard let best = playlist.bestVariant else { throw DownloadError.emptyPlaylist }
                let mediaText = try await HLSClient.getText(url: best.url, referer: referer)
                playlist = try HLSParser.parse(text: mediaText, url: best.url)
                target = best.url
            }
            guard !playlist.segments.isEmpty else { throw DownloadError.emptyPlaylist }
            if playlist.usesSampleAES { throw DownloadError.sampleAES }
            store.startRemote(
                playlistURL: stream.url,
                variantURL: target,
                title: stream.displayTitle,
                referer: referer,
                format: .mp4,
                saveToPhotos: false
            )
            return .queued(segments: playlist.segments.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 直链（mp4/mp3 等）直接入队，走单文件下载。
    @MainActor
    @discardableResult
    static func directDownload(_ stream: SniffedStream, sniffer: Sniffer, store: DownloadStore) -> DownloadJob? {
        guard stream.kind == .file else { return nil }
        return store.startDirect(
            url: stream.url,
            title: stream.displayTitle,
            referer: sniffer.referer(for: stream),
            saveToPhotos: false
        )
    }

    /// 不能直接下载时的统一提示文案。
    static func unsupportedReason(for stream: SniffedStream) -> String {
        switch stream.kind {
        case .dash: return "DASH（.mpd）暂不支持下载，可复制链接用其他工具"
        case .file: return "直链资源请在详情页里使用“直接下载”"
        case .hls: return "播放列表解析失败"
        }
    }
}
