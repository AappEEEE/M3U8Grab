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
                if store.jobs.isEmpty { emptyState }
                else {
                    List {
                        if store.activeCount > 0 {
                            Section {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("正在下载 \(store.activeCount) 个任务")
                                        .font(.footnote).foregroundColor(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Section {
                            ForEach(store.jobs) { job in
                                JobRow(job: job, store: store) { selectedJob = job }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) { store.remove(job, deleteFile: true) } label: { Label("删除", systemImage: "trash") }
                                            .disabled(job.isStopping)
                                        if job.phase == .finished, let url = job.outputURL {
                                            Button { shareItem = SharedFile(url: url) } label: { Label("分享", systemImage: "square.and.arrow.up") }.tint(.blue)
                                        }
                                    }
                            }
                        } footer: {
                            Text("文件保存在「文件」App › 我的 iPhone › M3U8 Grab › Downloads。")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("下载")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { store.clearFinished() } label: { Label("清理已完成任务", systemImage: "trash") }
                        Button { showSettings = true } label: { Label("设置", systemImage: "gearshape") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $selectedJob) { JobDetailSheet(job: $0, store: store) }
            .sheet(isPresented: $showSettings) { SettingsSheet(store: store) }
            .sheet(item: $shareItem) { ActivityView(items: [$0.url]) }
            .overlay(alignment: .bottom) {
                if let toast = store.toast {
                    Text(toast).font(.footnote.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial).clipShape(Capsule()).padding(.bottom, 18).transition(.opacity)
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { store.toast = nil } } }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle").font(.system(size: 52, weight: .light)).foregroundColor(.secondary)
            Text("没有下载任务").font(.headline)
            Text("从「嗅探」里选一个流，或去「工具」手动粘贴 m3u8 地址。")
                .font(.footnote).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct JobRow: View {
    @ObservedObject var job: DownloadJob
    @ObservedObject var store: DownloadStore
    let showDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: showDetails) {
                details
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看任务详情")
            actions
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: iconName).foregroundColor(iconColor).frame(width: 22)
                Text(job.title).font(.subheadline.weight(.medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                Text(job.format.displayName).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .fixedSize()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            }
            if job.phase.isActive || job.phase == .paused { ProgressView(value: job.progress).progressViewStyle(.linear) }
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.statusText).font(.caption2).foregroundColor(job.phase == .failed ? .red : .secondary).lineLimit(2)
                    if job.phase == .downloading {
                        Label(job.speedText, systemImage: "arrow.down")
                            .font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                        if let eta = job.etaText {
                            Text("剩余 \(eta)").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                        }
                    }
                    if let error = job.errorText, job.phase != .finished {
                        Text(error).font(.caption2).foregroundColor(.red).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                if job.phase == .finished {
                    Text(job.outputSizeText).font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var actions: some View {
        if job.phase.isActive || job.phase == .paused || job.phase == .failed || job.phase == .cancelled {
            HStack(spacing: 12) {
                if job.isStopping {
                    ProgressView().controlSize(.small)
                    Text("正在停止，请稍候…").font(.caption).foregroundColor(.secondary)
                } else if job.phase.isActive {
                    if job.canPause {
                        Button { store.pause(job) } label: { Label("暂停", systemImage: "pause.fill").frame(minHeight: 32) }
                            .accessibilityLabel("暂停下载")
                    }
                    Button(role: .destructive) { store.cancel(job) } label: { Label("取消", systemImage: "xmark").frame(minHeight: 32) }
                        .accessibilityLabel("取消下载")
                } else {
                    Button { store.resume(job) } label: {
                        Label(job.phase == .cancelled ? "重新下载" : "继续下载", systemImage: "play.fill").frame(minHeight: 32)
                    }
                    if job.phase == .paused {
                        Button(role: .destructive) { store.cancel(job) } label: { Label("取消", systemImage: "xmark").frame(minHeight: 32) }
                    }
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
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
        case .paused: return "pause.circle.fill"
        }
    }
    private var iconColor: Color {
        switch job.phase {
        case .finished: return .green
        case .failed: return .red
        case .cancelled, .paused: return .secondary
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
                    if job.duration > 0 { labeled("时长", formatDuration(job.duration)) }
                    if job.totalSegments > 0 { labeled("分片", "\(job.totalSegments)") }
                    if job.phase.isActive || job.phase == .paused || job.phase == .failed {
                        labeled("进度", String(format: "%.1f%%", job.progress * 100))
                        ProgressView(value: job.progress).progressViewStyle(.linear)
                    }
                    labeled("详情", job.statusText)
                    if job.phase == .downloading { labeled("速度", job.speedText); if let eta = job.etaText { labeled("预计剩余", eta) } }
                    if job.phase == .finished { labeled("大小", job.outputSizeText) }
                }
                if let error = job.errorText {
                    Section("提示") { Text(error).font(.caption).foregroundColor(.red) }
                }
                Section {
                    if job.isStopping {
                        HStack { ProgressView(); Text("正在停止，请稍候…").foregroundColor(.secondary) }
                    } else if job.phase.isActive {
                        if job.canPause {
                            Button { store.pause(job) } label: { Label("暂停下载", systemImage: "pause.circle") }
                        }
                        Button(role: .destructive) { store.cancel(job) } label: { Label("取消下载", systemImage: "xmark.circle") }
                    } else if job.phase == .failed || job.phase == .cancelled || job.phase == .paused {
                        Button { store.resume(job) } label: { Label(job.phase == .cancelled ? "重新下载" : "继续下载", systemImage: "play.circle") }
                        if job.phase == .paused {
                            Button(role: .destructive) { store.cancel(job) } label: { Label("取消下载", systemImage: "xmark.circle") }
                        }
                    }
                    if job.phase == .finished, let url = job.outputURL {
                        Button { share = SharedFile(url: url) } label: { Label("分享 / 导出", systemImage: "square.and.arrow.up") }
                        Button { store.saveToPhotos(job) } label: { Label(job.savedToPhotos ? "已保存到相册" : "保存到相册", systemImage: "photo.on.rectangle") }.disabled(job.savedToPhotos)
                    }
                    Button(role: .destructive) { store.remove(job, deleteFile: true); dismiss() } label: { Label("删除任务与文件", systemImage: "trash") }
                        .disabled(job.isStopping)
                }
            }
            .listStyle(.insetGrouped).navigationTitle("任务详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $share) { ActivityView(items: [$0.url]) }
    }

    private func labeled(_ name: String, _ value: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption).foregroundColor(.secondary)
            Text(value).font(small ? .caption2 : .subheadline).textSelection(.enabled).lineLimit(small ? 3 : 2)
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
                        HStack { Text("并发分片数"); Spacer(); Text("\(store.concurrency)").foregroundColor(.secondary).monospacedDigit() }
                    }
                    Toggle("下载完成后自动存相册", isOn: $store.autoSaveToPhotos)
                } footer: { Text("默认并发 8。并发越高通常越快，但站点可能限速；遇到 403 或不稳定可降至 2–4。失败分片会在主体下载后以较低并发重试。") }
                Section { Button { openFolderInFiles(Paths.downloads) } label: { Label("在「文件」App 中打开下载目录", systemImage: "folder") } }
            }
            .navigationTitle("下载设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }
}
