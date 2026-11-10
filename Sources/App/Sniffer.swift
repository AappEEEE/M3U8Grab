import Foundation
import Combine

/// 嗅探结果仓库：负责 JS 回传消息的解析、去重、排序
@MainActor
final class Sniffer: ObservableObject {
    @Published private(set) var streams: [SniffedStream] = []
    @Published var currentPageURL: URL?
    @Published var currentPageTitle: String = ""
    @Published var isSniffingEnabled: Bool = true
    @Published var lastRejected: String?

    /// 去重键 = url + kind
    private var index: [String: UUID] = [:]

    func resetForNewPage(url: URL?, title: String) {
        currentPageURL = url
        currentPageTitle = title.isEmpty ? (url?.host ?? "") : title
    }

    func clear() {
        streams.removeAll()
        index.removeAll()
    }

    /// 处理来自 WKScriptMessage 的字典
    func ingest(message: [String: Any]) {
        guard isSniffingEnabled else { return }
        guard let rawURL = message["url"] as? String else { return }
        let kindString = ((message["kind"] as? String) ?? "hls").lowercased()
        let kind: StreamKind
        switch kindString {
        case "dash", "mpd": kind = .dash
        case "file": kind = .file
        default: kind = .hls
        }

        let pageURLString = message["pageURL"] as? String
        let pageTitle = (message["pageTitle"] as? String) ?? ""

        add(urlString: rawURL, kind: kind, pageURLString: pageURLString, pageTitle: pageTitle)
    }

    func add(urlString: String, kind: StreamKind, pageURLString: String?, pageTitle: String) {
        guard let url = URL(string: urlString), url.scheme?.lowercased().hasPrefix("http") == true else {
            lastRejected = urlString
            return
        }

        let key = url.absoluteString
        if let existingID = index[key], let position = streams.firstIndex(where: { $0.id == existingID }) {
            // 已存在：仅刷新页面信息
            if streams[position].pageTitle == nil, !pageTitle.isEmpty {
                streams[position] = SniffedStream(
                    id: existingID,
                    url: url,
                    pageURL: URL(string: pageURLString ?? ""),
                    pageTitle: pageTitle,
                    kind: kind,
                    discoveredAt: streams[position].discoveredAt
                )
            }
            return
        }

        let stream = SniffedStream(
            url: url,
            pageURL: URL(string: pageURLString ?? currentPageURL?.absoluteString ?? ""),
            pageTitle: pageTitle.isEmpty ? nil : pageTitle,
            kind: kind,
            discoveredAt: Date()
        )
        index[key] = stream.id
        streams.insert(stream, at: 0)
    }

    var hlsCount: Int { streams.filter { $0.kind == .hls }.count }

    func remove(_ stream: SniffedStream) {
        streams.removeAll { $0.id == stream.id }
        index.removeValue(forKey: stream.url.absoluteString)
    }

    /// 给下载任务用的 Referer：优先取该流所在页面
    func referer(for stream: SniffedStream) -> String? {
        if let pageURL = stream.pageURL, let host = pageURL.host {
            return "\(pageURL.scheme ?? "https")://\(host)/"
        }
        return currentPageURL?.host.map { _ in currentPageURL!.absoluteString }
    }
}
