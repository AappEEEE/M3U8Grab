import SwiftUI

struct StreamDetailView: View {
    let stream: SniffedStream
    @ObservedObject var engine: BrowserEngine
    @ObservedObject var sniffer: Sniffer
    @ObservedObject var store: DownloadStore

    @State private var playlist: HLSPlaylist?
    @State private var isLoadingPlaylist = false
    @State private var loadError: String?
    @State private var selectedVariantURL: URL?
    @State private var format: OutputFormat = .mp4
    @State private var saveToPhotos = false
    @State private var concurrency = 6
    @State private var showPlayer = false
    @State private var started = false

    private var referer: String? { sniffer.referer(for: stream) }

    private var variantOptions: [VariantOption] {
        (playlist?.sortedVariants ?? []).map { VariantOption(variant: $0) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stream.url.lastPathComponent.isEmpty ? (stream.url.host ?? "播放列表") : stream.url.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(stream.url.absoluteString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)

                HStack {
                    Button {
                        showPlayer = true
                    } label: {
                        Label("预览播放", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyToPasteboard(stream.url.absoluteString)
                        store.toast = "链接已复制"
                    } label: {
                        Label("复制链接", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    copyToPasteboard(curlCommand())
                    store.toast = "已复制 curl 命令（含 Referer）"
                } label: {
                    Label("复制 curl 命令", systemImage: "terminal")
                        .font(.footnote)
                }
            }

            Section("播放列表信息") {
                if stream.kind == .dash {
                    infoRow("类型", "DASH 播放列表（.mpd）")
                    Text("DASH 需要单独的解析与切片合并流程，当前版本暂不支持下载；可以用「复制链接」交给其他工具。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if stream.kind == .file {
                    infoRow("扩展名", stream.url.pathExtension.isEmpty ? "未知" : stream.url.pathExtension.lowercased())
                    Text("单文件直链会原样保存，不做转码；支持断点续传。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if isLoadingPlaylist {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("解析中…").foregroundColor(.secondary).font(.footnote)
                    }
                } else if let error = loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundColor(.orange)
                        Button("重试") {
                            Task { await inspect() }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                } else if let playlist {
                    infoRow("类型", playlist.isMaster ? "主播放列表（多清晰度）" : "媒体播放列表")
                    if playlist.isMaster {
                        infoRow("清晰度数量", "\(playlist.variants.count)")
                    } else {
                        infoRow("分片数量", "\(playlist.segments.count)")
                        infoRow("总时长", formatDuration(playlist.totalDuration))
                        infoRow("加密", playlist.isEncrypted ? (playlist.usesSampleAES ? "SAMPLE-AES（不支持）" : "AES-128") : "无")
                        if playlist.hasInitMap {
                            infoRow("容器", "fMP4（init 段）")
                        }
                        infoRow("状态", playlist.isLive ? "直播流（可能不完整）" : "点播 VOD")
                    }
                } else {
                    Button("解析播放列表") {
                        Task { await inspect() }
                    }
                }
            }

            if playlist?.isMaster == true {
                Section("选择清晰度") {
                    ForEach(variantOptions) { option in
                        Button {
                            selectedVariantURL = option.url
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                    Text(option.detail)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if isSelected(option) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }

            if stream.kind == .hls {
                Section("导出设置") {
                    Picker("格式", selection: $format) {
                        ForEach(OutputFormat.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(format.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Toggle("完成后保存到相册", isOn: $saveToPhotos)

                    Stepper(value: $concurrency, in: 1...16) {
                        HStack {
                            Text("并发分片数")
                            Spacer()
                            Text("\(concurrency)")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                Button {
                    startDownload()
                } label: {
                    HStack {
                        Spacer()
                        Label(
                            started ? "已加入下载队列"
                                : (stream.kind == .hls ? "开始下载" : (stream.kind == .dash ? "DASH 暂不支持" : "直接下载")),
                            systemImage: started ? "checkmark.circle.fill" : "arrow.down.circle.fill"
                        )
                        .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(stream.kind == .dash || isLoadingPlaylist || (stream.kind == .hls && playlist?.isMaster == true && selectedVariantURL == nil))
            } footer: {
                Text(stream.kind == .hls
                     ? "下载过程中可以切到「下载」页看进度；分片会随时落盘，中断后重试会续传已下载部分。"
                     : (stream.kind == .dash
                        ? "DASH 暂不支持下载。"
                        : "直链文件边下边存，可暂停、可续传；完成后在「下载」页分享或保存。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("流详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            concurrency = store.concurrency
            saveToPhotos = store.autoSaveToPhotos
            if stream.kind == .hls { await inspect() }
        }
        .sheet(isPresented: $showPlayer) {
            PlayerSheet(
                title: stream.displayTitle,
                url: selectedVariantURL ?? stream.url,
                referer: referer
            )
        }
    }

    // MARK: - 行为

    private func isSelected(_ option: VariantOption) -> Bool {
        selectedVariantURL == option.url
    }

    private func infoRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }

    private func inspect() async {
        isLoadingPlaylist = true
        loadError = nil
        defer { isLoadingPlaylist = false }
        do {
            let text = try await HLSClient.getText(url: stream.url, referer: referer)
            let parsed = try HLSParser.parse(text: text, url: stream.url)
            playlist = parsed
            if parsed.isMaster {
                selectedVariantURL = parsed.bestVariant?.url
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 生成可直接在电脑终端执行的 curl 命令，方便把嗅探到的地址丢给外部工具。
    private func curlCommand() -> String {
        let target = selectedVariantURL ?? stream.url
        var lines: [String] = []
        lines.append("curl -L --fail --retry 3 \\")
        lines.append("  -A \"\(HLSClient.userAgent)\" \\")
        if let referer {
            lines.append("  -e \"\(referer)\" \\")
        }
        let name = sanitizeFileName(stream.displayTitle)
        lines.append("  -o \"\(name).ts\" \\")
        lines.append("  \"\(target.absoluteString)\"")
        return lines.joined(separator: "\n")
    }

    private func startDownload() {
        guard stream.kind != .dash else { return }
        if stream.kind == .file {
            store.startDirect(
                url: stream.url,
                title: stream.displayTitle,
                referer: referer,
                saveToPhotos: saveToPhotos
            )
            started = true
            store.toast = "已开始下载直链文件"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                started = false
            }
            return
        }
        let variant = selectedVariantURL
        store.concurrency = concurrency
        let title = stream.displayTitle
        store.startRemote(
            playlistURL: stream.url,
            variantURL: variant,
            title: title,
            referer: referer,
            format: format,
            saveToPhotos: saveToPhotos
        )
        started = true
        store.toast = "已加入下载队列"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            started = false
        }
    }
}
