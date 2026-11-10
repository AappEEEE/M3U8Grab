import SwiftUI

struct StreamsTab: View {
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var sniffer: Sniffer
    @ObservedObject var store: DownloadStore
    @Binding var selectedTab: Int
    @State private var quickTasks: Set<UUID> = []
    @State private var query = ""
    @State private var filter: KindFilter = .all

    enum KindFilter: String, CaseIterable, Identifiable {
        case all, hls, file

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .hls: return "M3U8"
            case .file: return "直链"
            }
        }
    }

    /// 搜索 + 类型筛选后的结果；列表与空态都基于它。
    private var visibleStreams: [SniffedStream] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sniffer.streams.filter { stream in
            switch filter {
            case .all: break
            case .hls: if stream.kind != .hls { return false }
            case .file: if stream.kind == .hls { return false }
            }
            guard !keyword.isEmpty else { return true }
            return stream.displayTitle.lowercased().contains(keyword)
                || stream.url.absoluteString.lowercased().contains(keyword)
                || (stream.pageTitle ?? "").lowercased().contains(keyword)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterBar
                if sniffer.streams.isEmpty {
                    emptyState
                } else if visibleStreams.isEmpty {
                    noMatchState
                } else {
                    streamList
                }
            }
            .navigationTitle("已嗅探")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索标题、域名或链接")
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

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("类型", selection: $filter) {
                ForEach(KindFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Spacer(minLength: 0)

            Text("\(visibleStreams.count)/\(sniffer.streams.count)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var streamList: some View {
        List {
            Section {
                ForEach(visibleStreams) { stream in
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
                        Button {
                            quickDownload(stream)
                        } label: {
                            Label(stream.kind == .hls ? "下载" : "直链下载", systemImage: "arrow.down.circle")
                        }
                        .tint(.green)
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

    private var noMatchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            Text("没有符合条件的资源")
                .font(.subheadline.weight(.medium))
            Button("清除筛选") {
                query = ""
                filter = .all
            }
            .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 右滑“下载”：解析播放列表并自动选最高码率；直链直接入队。
    @MainActor
    private func quickDownload(_ stream: SniffedStream) {
        if stream.kind == .file {
            if StreamActions.directDownload(stream, sniffer: sniffer, store: store) != nil {
                store.toast = "已开始下载直链文件"
                selectedTab = 2
            }
            return
        }
        guard stream.kind == .hls, !quickTasks.contains(stream.id) else {
            store.toast = StreamActions.unsupportedReason(for: stream)
            return
        }
        quickTasks.insert(stream.id)
        Task {
            let outcome = await StreamActions.quickDownload(stream, sniffer: sniffer, store: store)
            quickTasks.remove(stream.id)
            store.toast = outcome.message
            if case .queued = outcome { selectedTab = 2 }
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
                    .fill((stream.kind == .hls ? Color.accentColor : Color.orange).opacity(0.15))
                Image(systemName: stream.kind.symbol)
                    .foregroundColor(stream.kind == .hls ? .accentColor : .orange)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(stream.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(stream.kind.badge)
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
