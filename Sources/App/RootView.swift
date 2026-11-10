import SwiftUI
import Combine
import UIKit

struct RootView: View {
    @StateObject private var sniffer: Sniffer
    @StateObject private var engine: BrowserEngine
    @StateObject private var store: DownloadStore
    @State private var selectedTab: Int = 0

    /// 剪贴板监听（默认关：iOS 16 起读取剪贴板会弹系统确认框）
    @AppStorage("clipboardWatch") private var clipboardWatch: Bool = false

    @State private var clipboardHint: String?
    @State private var lastClipboardValue: String = ""

    @MainActor
    init() {
        let sniffer = Sniffer()
        _sniffer = StateObject(wrappedValue: sniffer)
        _engine = StateObject(wrappedValue: BrowserEngine(sniffer: sniffer))
        _store = StateObject(wrappedValue: DownloadStore())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowserTab(engine: engine, sniffer: sniffer, store: store, selectedTab: $selectedTab)
                .tabItem {
                    Label("浏览器", systemImage: "safari")
                }
                .tag(0)

            StreamsTab(engine: engine, sniffer: sniffer, store: store, selectedTab: $selectedTab)
                .tabItem {
                    Label("嗅探", systemImage: "dot.radiowaves.left.and.right")
                }
                .badge(sniffer.streams.count)
                .tag(1)

            DownloadsTab(store: store, sniffer: sniffer)
                .tabItem {
                    Label("下载", systemImage: "arrow.down.circle")
                }
                .tag(2)

            ToolsTab(engine: engine, sniffer: sniffer, store: store)
                .tabItem {
                    Label("工具", systemImage: "wrench.and.screwdriver")
                }
                .tag(3)
        }
        .accentColor(.accentColor)
        .overlay(alignment: .top) {
            if let hint = clipboardHint {
                clipboardBanner(url: hint)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: clipboardHint)
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard clipboardWatch else { return }
            // 稍微延迟，避免和启动动画 / 深链处理互相打断
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                inspectClipboard()
            }
        }
    }

    // MARK: - 剪贴板

    private func inspectClipboard() {
        guard clipboardWatch else { return }
        guard let raw = UIPasteboard.general.string else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != lastClipboardValue else { return }
        guard text.count > 8, text.count < 8192 else { return }
        guard text.lowercased().hasPrefix("http") else { return }

        let lowered = text.lowercased()
        let looksLikePlaylist = lowered.contains(".m3u8") || lowered.contains("m3u8?")
            || lowered.contains("playlist") || lowered.contains(".m3u")
        guard looksLikePlaylist else { return }

        lastClipboardValue = text
        clipboardHint = firstURL(in: text) ?? text
    }

    private func firstURL(in text: String) -> String? {
        // 剪贴板里可能是「标题 + 链接」混合文本，抓第一段 http(s) 地址
        guard let range = text.range(of: "http", options: [.caseInsensitive]) else { return nil }
        let tail = String(text[range.lowerBound...])
        let terminators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>（）()【】"))
        if let end = tail.rangeOfCharacter(from: terminators) {
            return String(tail[..<end.lowerBound])
        }
        return tail
    }

    private func clipboardBanner(url: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("剪贴板里有 M3U8 链接")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                Text(url)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer()
            Button("加入") {
                addToSniffer(urlString: url, pageURL: nil, title: nil)
                clipboardHint = nil
            }
            .font(.footnote.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.22))
            .foregroundColor(.white)
            .clipShape(Capsule())
            Button {
                clipboardHint = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
    }

    // MARK: - 深链

    /// 支持的形式：
    ///   m3u8grab://open?url=<编码后的播放列表>&page=<页面地址>&title=<标题>
    ///   m3u8grab://?url=...                       （旧写法）
    ///   m3u8grab://open?url=A&url=B               （一次多条）
    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "m3u8grab" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        let page = items.first(where: { $0.name == "page" })?.value
        let title = items.first(where: { $0.name == "title" })?.value

        let targets = items
            .filter { $0.name == "url" || $0.name == "u" }
            .compactMap { $0.value }
            .filter { !$0.isEmpty }

        guard !targets.isEmpty else {
            // 没有参数：把用户带回嗅探页，方便手动粘贴
            selectedTab = 1
            return
        }

        for target in targets {
            addToSniffer(urlString: target, pageURL: page, title: title)
        }
        selectedTab = 1
    }

    private func addToSniffer(urlString: String, pageURL: String?, title: String?) {
        let lowered = urlString.lowercased()
        let kind: StreamKind
        if lowered.contains(".mpd") {
            kind = .dash
        } else if lowered.contains(".m3u8") || lowered.contains(".m3u") {
            kind = .hls
        } else {
            kind = .file
        }
        sniffer.add(
            urlString: urlString,
            kind: kind,
            pageURLString: pageURL,
            pageTitle: title ?? ""
        )
    }
}
