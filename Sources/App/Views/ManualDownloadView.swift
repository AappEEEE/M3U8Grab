import SwiftUI

struct ManualDownloadView: View {
    @ObservedObject var store: DownloadStore

    enum Mode: String, CaseIterable, Identifiable {
        case link, text
        var id: String { rawValue }
        var title: String { self == .link ? "链接" : "播放列表文本" }
    }

    @State private var mode: Mode = .link
    @State private var linkText = ""
    @State private var textBody = ""
    @State private var baseURLText = ""
    @State private var format: OutputFormat = .mp4
    @State private var saveToPhotos = false
    @State private var concurrency = 6
    @State private var preview: String?
    @State private var previewError: String?
    @State private var parsing = false

    var body: some View {
        Form {
            Section {
                Picker("输入方式", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if mode == .link {
                Section {
                    TextField("https://example.com/index.m3u8", text: $linkText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                } header: {
                    Text("播放列表地址")
                } footer: {
                    Text("支持主播放列表（自动选最高码率）和媒体播放列表。")
                }
            } else {
                Section {
                    TextEditor(text: $textBody)
                        .frame(minHeight: 150)
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("基准地址，例如 https://cdn.example.com/hls/", text: $baseURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                } header: {
                    Text("播放列表内容")
                } footer: {
                    Text("分段是相对路径时必须填基准地址；若文本里已有 #EXT-X-KEY 的绝对地址则可省略。")
                }
            }

            Section {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                }
                Button {
                    Task { await runPreview() }
                } label: {
                    HStack {
                        Label("解析预览", systemImage: "magnifyingglass")
                        Spacer()
                        if parsing { ProgressView() }
                    }
                }
                .disabled(parsing || !hasInput)
            }

            if let preview {
                Section("解析结果") {
                    Text(preview)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            if let previewError {
                Section("解析失败") {
                    Text(previewError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("导出设置") {
                Picker("格式", selection: $format) {
                    ForEach(OutputFormat.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("完成后保存到相册", isOn: $saveToPhotos)
                Stepper(value: $concurrency, in: 1...16) {
                    HStack {
                        Text("并发分片数")
                        Spacer()
                        Text("\(concurrency)").foregroundColor(.secondary).monospacedDigit()
                    }
                }
            }

            Section {
                Button {
                    start()
                } label: {
                    HStack {
                        Spacer()
                        Label("开始下载", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasInput)
            }
        }
        .navigationTitle("手动下载")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            concurrency = store.concurrency
            saveToPhotos = store.autoSaveToPhotos
            if linkText.isEmpty, mode == .link,
               let clip = UIPasteboard.general.string,
               clip.lowercased().contains(".m3u8") {
                linkText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private var hasInput: Bool {
        mode == .link ? !linkText.trimmingCharacters(in: .whitespaces).isEmpty
                      : !textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pasteFromClipboard() {
        guard let clip = UIPasteboard.general.string else { return }
        if mode == .link {
            linkText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            textBody = clip
        }
    }

    private func runPreview() async {
        parsing = true
        preview = nil
        previewError = nil
        defer { parsing = false }

        if mode == .link {
            let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed) else {
                previewError = "地址不合法"
                return
            }
            do {
                let text = try await HLSClient.getText(url: url, referer: nil)
                let playlist = try HLSParser.parse(text: text, url: url)
                preview = describe(playlist)
            } catch {
                previewError = error.localizedDescription
            }
        } else {
            let base = URL(string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let base else {
                previewError = "请填写有效的基准地址"
                return
            }
            do {
                let playlist = try HLSParser.parse(text: textBody, url: base)
                preview = describe(playlist)
            } catch {
                previewError = error.localizedDescription
            }
        }
    }

    private func describe(_ playlist: HLSPlaylist) -> String {
        var lines: [String] = []
        lines.append("类型：\(playlist.isMaster ? "主播放列表" : "媒体播放列表")")
        if playlist.isMaster {
            lines.append("清晰度：\(playlist.variants.count) 个")
            for variant in playlist.sortedVariants.prefix(6) {
                lines.append("· \(variant.displayLabel)")
            }
        } else {
            lines.append("分片：\(playlist.segments.count) 个")
            lines.append("时长：\(formatDuration(playlist.totalDuration))")
            lines.append("加密：\(playlist.isEncrypted ? (playlist.usesSampleAES ? "SAMPLE-AES（不支持）" : "AES-128") : "无")")
            lines.append("容器：\(playlist.hasInitMap ? "fMP4" : "TS")")
            lines.append("状态：\(playlist.isLive ? "直播" : "点播")")
        }
        return lines.joined(separator: "\n")
    }

    private func start() {
        store.concurrency = concurrency
        let title: String
        if mode == .link {
            let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed) else { return }
            title = url.deletingPathExtension().lastPathComponent.isEmpty
                ? (url.host ?? "video")
                : url.deletingPathExtension().lastPathComponent
            store.startRemote(
                playlistURL: url,
                title: title,
                referer: nil,
                format: format,
                saveToPhotos: saveToPhotos
            )
        } else {
            let base = URL(string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? URL(string: "https://localhost/")!
            title = "manual-\(Int(Date().timeIntervalSince1970))"
            store.startInline(
                text: textBody,
                baseURL: base,
                title: title,
                format: format,
                saveToPhotos: saveToPhotos
            )
        }
        store.toast = "已加入下载队列"
    }
}
