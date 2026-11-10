import SwiftUI

struct StreamsTab: View {
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var sniffer: Sniffer
    @ObservedObject var store: DownloadStore
    @Binding var selectedTab: Int
    @State private var quickTasks: Set<UUID> = []

    var body: some View {
        NavigationView {
            Group {
                if sniffer.streams.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(sniffer.streams) { stream in
                                NavigationLink {
                                    StreamDetailView(
                                        stream: stream,
                                        engine: engine,
                                        sniffer: sniffer,
                                        store: store
                                    )
                                } label: {
                                    StreamRow(stream: stream, isPreparing: quickTasks.contains(stream.id))
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if stream.kind == .hls {
                                        Button {
                                            Task { await quickDownload(stream) }
                                        } label: {
                                            Label("下载", systemImage: "arrow.down.circle")
                                        }
                                        .tint(.green)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        sniffer.remove(stream)
                                    } label: {
                                        Label("移除", systemImage: "trash")
                                    }
                                    Button {
                                        copyToPasteboard(stream.url.absoluteString)
                                        store.toast = "链接已复制"
                                    } label: {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                            }
                        } header: {
                            Text("共 \(sniffer.streams.count) 条 · \(sniffer.hlsCount) 个 M3U8")
                        } footer: {
                            Text("在「浏览器」里播放视频后，地址会被自动抓取。右滑可直接下载最高清晰度；切换页面不会清空列表。")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("已嗅探")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            selectedTab = 0
                        } label: {
                            Label("回到浏览器继续嗅探", systemImage: "safari")
                        }
                        Button {
                            sniffer.isSniffingEnabled.toggle()
                        } label: {
                            Label(sniffer.isSniffingEnabled ? "暂停嗅探" : "恢复嗅探",
                                  systemImage: sniffer.isSniffingEnabled ? "pause.circle" : "play.circle")
                        }
                        Divider()
                        Button(role: .destructive) {
                            sniffer.clear()
                        } label: {
                            Label("清空列表", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    /// 右滑“下载”：解析播放列表并自动选最高码率，省去进入详情页选清晰度的步骤。
    @MainActor
    private func quickDownload(_ stream: SniffedStream) async {
        guard stream.kind == .hls, !quickTasks.contains(stream.id) else { return }
        quickTasks.insert(stream.id)
        defer { quickTasks.remove(stream.id) }
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
            store.toast = "已加入下载 · \(playlist.segments.count) 个分片"
            selectedTab = 2
        } catch {
            store.toast = "加入失败：\(error.localizedDescription)"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 52, weight: .light))
                .foregroundColor(.secondary)
            Text("还没有嗅探到视频")
                .font(.headline)
            Text("去「浏览器」打开任意视频网站并开始播放，\nM3U8 与直链地址会自动出现在这里。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button {
                selectedTab = 0
            } label: {
                Label("打开浏览器", systemImage: "safari")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
            .padding(.top, 4)
        }
        .padding(32)
    }
}

struct StreamRow: View {
    let stream: SniffedStream
    var isPreparing: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(stream.kind == .hls ? Color.accentColor.opacity(0.15) : Color.orange.opacity(0.15))
                Image(systemName: stream.kind == .hls ? "list.bullet.rectangle.play" : "doc.fill")
                    .foregroundColor(stream.kind == .hls ? .accentColor : .orange)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(stream.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(stream.kind == .hls ? "M3U8" : "文件")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(stream.hostText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isPreparing {
                ProgressView().controlSize(.small)
            } else {
                Text(stream.discoveredAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
