import SwiftUI

/// 浏览器右下角悬浮球点开的资源面板：只显示当前页面嗅探到的内容。
struct SniffedPanelSheet: View {
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var sniffer: Sniffer
    @ObservedObject var store: DownloadStore
    @Binding var selectedTab: Int

    @Environment(\.dismiss) private var dismiss
    @State private var busy: Set<UUID> = []
    @State private var hint: String?

    var body: some View {
        NavigationView {
            Group {
                if sniffer.streams.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.secondary)
                        Text("当前页面还没有发现资源")
                            .font(.subheadline.weight(.medium))
                        Text("播放一下视频，或等页面加载完再看。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(sniffer.streams) { stream in
                                NavigationLink {
                                    StreamDetailView(stream: stream, engine: engine, sniffer: sniffer, store: store)
                                } label: {
                                    SniffedPanelRow(stream: stream, busy: busy.contains(stream.id))
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        queue(stream)
                                    } label: {
                                        Label(stream.kind == .hls ? "下载" : "直链下载", systemImage: "arrow.down.circle")
                                    }
                                    .tint(.accentColor)

                                    Button {
                                        copyToPasteboard(stream.url.absoluteString)
                                        hint = "链接已复制"
                                    } label: {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                    .tint(.orange)
                                }
                            }
                        } footer: {
                            Text("点条目看详情；左滑可直接下载或复制链接。列表汇总了本次浏览抓到的全部资源。")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("已嗅探 \(sniffer.streams.count) 个资源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清空") {
                        sniffer.clear()
                        hint = "已清空本页记录"
                    }
                    .disabled(sniffer.streams.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let hint {
                    Text(hint)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.78)))
                        .padding(.bottom, 18)
                        .transition(.opacity)
                        .onTapGesture { self.hint = nil }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @MainActor
    private func queue(_ stream: SniffedStream) {
        guard !busy.contains(stream.id) else { return }
        if stream.kind == .file {
            if StreamActions.directDownload(stream, sniffer: sniffer, store: store) != nil {
                hint = "已开始下载直链文件"
            }
            return
        }
        guard stream.kind == .hls else {
            hint = StreamActions.unsupportedReason(for: stream)
            return
        }
        busy.insert(stream.id)
        Task { @MainActor in
            let outcome = await StreamActions.quickDownload(stream, sniffer: sniffer, store: store)
            busy.remove(stream.id)
            hint = outcome.message
        }
    }
}

private struct SniffedPanelRow: View {
    let stream: SniffedStream
    let busy: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((stream.kind == .hls ? Color.accentColor : Color.orange).opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: stream.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(stream.kind == .hls ? .accentColor : .orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(stream.url.absoluteString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if busy {
                ProgressView().scaleEffect(0.8)
            } else {
                Text(stream.kind.badge)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
