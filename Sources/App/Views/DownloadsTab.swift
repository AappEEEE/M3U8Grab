import SwiftUI

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct DownloadsTab: View {
    @ObservedObject var store: DownloadStore
    @ObservedObject var sniffer: Sniffer

    @State private var selectedJob: DownloadJob?
    @State private var shareItem: SharedFile?
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            Group {
                if store.jobs.isEmpty {
                    emptyState
                } else {
                    List {
                        if store.activeCount > 0 {
                            Section {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("正在下载 \(store.activeCount) 个任务")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Section {
                            ForEach(store.jobs) { job in
                                Button {
                                    selectedJob = job
                                } label: {
                                    JobRow(job: job)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.remove(job, deleteFile: true)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    if job.phase == .finished {
                                        Button {
                                            if let url = job.outputURL {
                                                shareItem = SharedFile(url: url)
                                            }
                                        } label: {
                                            Label("分享", systemImage: "square.and.arrow.up")
                                        }
                                        .tint(.blue)
                                    }
                                }
                            }
                        } footer: {
                            Text("文件保存在「文件」App › 我的 iPhone › M3U8 Grab › Downloads。")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("下载")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            store.clearFinished()
                        } label: {
                            Label("清理已结束任务", systemImage: "trash")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $selectedJob) { job in
                JobDetailSheet(job: job, store: store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(store: store)
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
            .overlay(alignment: .bottom) {
                if let toast = store.toast {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 18)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation { store.toast = nil }
                            }
                        }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundColor(.secondary)
            Text("没有下载任务")
                .font(.headline)
            Text("从「嗅探」里选一个流，或去「工具」手动粘贴 m3u8 地址。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
    }
}

struct JobRow: View {
    @ObservedObject var job: DownloadJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .frame(width: 20)
                Text(job.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(job.format.displayName)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            if job.phase.isActive {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
            }

            HStack {
                Text(job.statusText)
                    .font(.caption2)
                    .foregroundColor(job.phase == .failed ? .red : .secondary)
                    .lineLimit(1)
                Spacer()
                if job.phase == .finished {
                    Text(job.outputSizeText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            if let error = job.errorText, job.phase != .finished {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch job.phase {
        case .queued: return "clock"
        case .fetching: return "antenna.radiowaves.left.and.right"
        case .downloading: return "arrow.down.circle"
        case .merging: return "square.stack.3d.down.right"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private var iconColor: Color {
        switch job.phase {
        case .finished: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        default: return .accentColor
        }
    }
}

struct JobDetailSheet: View {
    @ObservedObject var job: DownloadJob
    @ObservedObject var store: DownloadStore
    @State private var share: SharedFile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("任务") {
                    labeled("标题", job.title)
                    labeled("来源", job.sourceURL.absoluteString, small: true)
                    labeled("格式", job.format.displayName)
                    labeled("状态", job.phase.displayName)
                    if job.duration > 0 {
                        labeled("时长", formatDuration(job.duration))
                    }
                    if job.totalSegments > 0 {
                        labeled("分片", "\(job.totalSegments)")
                    }
                    if job.phase.isActive {
                        labeled("进度", String(format: "%.1f%%", job.progress * 100))
                    }
                    if job.phase == .finished {
                        labeled("大小", job.outputSizeText)
                    }
                }

                if let error = job.errorText {
                    Section("提示") {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    if job.phase.isActive {
                        Button(role: .destructive) {
                            store.cancel(job)
                        } label: {
                            Label("取消下载", systemImage: "xmark.circle")
                        }
                    } else if job.phase == .failed || job.phase == .cancelled {
                        Button {
                            store.retry(job)
                            dismiss()
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                        }
                    }

                    if job.phase == .finished, job.outputURL != nil {
                        Button {
                            if let url = job.outputURL {
                                share = SharedFile(url: url)
                            }
                        } label: {
                            Label("分享 / 导出", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            store.saveToPhotos(job)
                        } label: {
                            Label(job.savedToPhotos ? "已保存到相册" : "保存到相册", systemImage: "photo.on.rectangle")
                        }
                        .disabled(job.savedToPhotos)
                    }

                    Button(role: .destructive) {
                        store.remove(job, deleteFile: true)
                        dismiss()
                    } label: {
                        Label("删除任务与文件", systemImage: "trash")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("任务详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $share) { item in
            ActivityView(items: [item.url])
        }
    }

    private func labeled(_ name: String, _ value: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(small ? .caption2 : .subheadline)
                .textSelection(.enabled)
                .lineLimit(small ? 3 : 2)
        }
        .padding(.vertical, 1)
    }
}

struct SettingsSheet: View {
    @ObservedObject var store: DownloadStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Stepper(value: $store.concurrency, in: 1...16) {
                        HStack {
                            Text("并发分片数")
                            Spacer()
                            Text("\(store.concurrency)")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Toggle("下载完成后自动存相册", isOn: $store.autoSaveToPhotos)
                } footer: {
                    Text("并发越高越快，但部分站点会限速或拦截，遇到 403 可降到 2~4。")
                }

                Section {
                    Button {
                        openFolderInFiles(Paths.downloads)
                    } label: {
                        Label("在「文件」中打开下载目录", systemImage: "folder")
                    }
                } footer: {
                    Text("已开启 UIFileSharingEnabled，可在「文件」App 里直接管理导出的视频。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
