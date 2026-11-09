import Foundation
import UIKit

/// 一个下载任务：解析 → 并发拉分片（可断点续传）→ 解密 → 合并 → 转封装 → 落盘/进相册
@MainActor
final class DownloadJob: ObservableObject, Identifiable {
    let id: UUID
    let sourceURL: URL
    let variantURL: URL?
    let inlineText: String?
    let referer: String?
    let format: OutputFormat
    let concurrency: Int
    let createdAt: Date
    var saveToPhotos: Bool

    @Published private(set) var title: String
    @Published private(set) var phase: DownloadPhase = .queued
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = "等待开始"
    @Published private(set) var outputURL: URL?
    @Published private(set) var errorText: String?
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var totalSegments: Int = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var savedToPhotos = false

    var onFinish: ((DownloadJob) -> Void)?

    private let keys = KeyCache()
    private var task: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var workspace: URL

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL,
        variantURL: URL? = nil,
        inlineText: String? = nil,
        referer: String? = nil,
        format: OutputFormat = .mp4,
        saveToPhotos: Bool = false,
        concurrency: Int = 6
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.variantURL = variantURL
        self.inlineText = inlineText
        self.referer = referer
        self.format = format
        self.saveToPhotos = saveToPhotos
        self.concurrency = max(1, min(concurrency, 16))
        self.createdAt = Date()
        self.workspace = Paths.workspaces.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    var isActive: Bool { phase.isActive }
    var outputSizeText: String {
        guard let outputURL else { return "" }
        return formatBytes(FileManager.default.fileSize(at: outputURL))
    }

    // MARK: - 控制

    func start() {
        guard task == nil, phase == .queued else { return }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase.isActive {
            phase = .cancelled
            statusText = "已取消"
            removeWorkspace()
            onFinish?(self)
        }
    }

    func saveToPhotoLibrary() {
        guard let outputURL else { return }
        Task {
            do {
                try await MediaSaver.saveVideoToPhotos(outputURL)
                self.savedToPhotos = true
                self.statusText = "已保存到相册"
            } catch {
                self.errorText = error.localizedDescription
            }
        }
    }

    // MARK: - 主流程

    private func run() async {
        beginBackgroundTask()
        defer { endBackgroundTask() }

        Paths.createIfNeeded(workspace)

        do {
            phase = .fetching
            statusText = "获取播放列表…"
            progress = 0.02

            var playlistURL = variantURL ?? sourceURL
            var text: String
            if let inlineText {
                text = inlineText
            } else {
                text = try await HLSClient.getText(url: playlistURL, referer: referer)
            }

            var playlist = try HLSParser.parse(text: text, url: playlistURL)

            if playlist.isMaster {
                guard let best = playlist.bestVariant else { throw DownloadError.emptyPlaylist }
                statusText = "已选清晰度：\(best.displayLabel)"
                playlistURL = best.url
                let mediaText = try await HLSClient.getText(url: best.url, referer: referer)
                playlist = try HLSParser.parse(text: mediaText, url: best.url)
            }

            guard !playlist.segments.isEmpty else { throw DownloadError.emptyPlaylist }
            if playlist.usesSampleAES { throw DownloadError.sampleAES }

            totalSegments = playlist.segments.count
            duration = playlist.totalDuration
            progress = 0.05
            try Task.checkCancellation()

            phase = .downloading
            statusText = "开始下载 \(totalSegments) 个分片"
            try await downloadSegments(playlist.segments)

            try Task.checkCancellation()
            phase = .merging
            statusText = playlist.hasInitMap ? "合并 fMP4 分片…" : "合并 \(totalSegments) 个分片…"
            progress = 0.87

            let segmentFiles: [URL] = (0..<playlist.segments.count).map { index in
                workspace.appendingPathComponent(segmentFileName(index))
            }

            var produced: URL

            if playlist.hasInitMap {
                // fMP4（EXT-X-MAP）：init 段 + 分片直拼即为合法 MP4
                guard let initFile = try await fetchInitMap(playlist) else { throw DownloadError.emptyPlaylist }
                let target = uniqueFileURL(directory: Paths.downloads, baseName: title, pathExtension: "mp4")
                let inputs = [initFile] + segmentFiles
                try await Task.detached(priority: .userInitiated) {
                    try FileMerger.merge(files: inputs, into: target)
                }.value
                produced = target
            } else {
                let rawTS = workspace.appendingPathComponent("merged.ts")
                try await Task.detached(priority: .userInitiated) {
                    try FileMerger.merge(files: segmentFiles, into: rawTS)
                }.value

                if format == .ts {
                    let target = uniqueFileURL(directory: Paths.downloads, baseName: title, pathExtension: "ts")
                    if FileManager.default.fileExists(atPath: target.path) {
                        try? FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.moveItem(at: rawTS, to: target)
                    produced = target
                } else {
                    let target = uniqueFileURL(directory: Paths.downloads, baseName: title, pathExtension: "mp4")
                    statusText = "无损转封装为 MP4…"
                    do {
                        try await Task.detached(priority: .userInitiated) {
                            try Remuxer.remuxToMP4(input: rawTS, output: target)
                        }.value
                        produced = target
                        try? FileManager.default.removeItem(at: rawTS)
                    } catch {
                        // 转封装失败时保底：TS 直接交付，不丢数据
                        let fallback = uniqueFileURL(directory: Paths.downloads, baseName: title, pathExtension: "ts")
                        if FileManager.default.fileExists(atPath: fallback.path) {
                            try? FileManager.default.removeItem(at: fallback)
                        }
                        try FileManager.default.moveItem(at: rawTS, to: fallback)
                        produced = fallback
                        errorText = "已保留 TS：\(error.localizedDescription)"
                    }
                }
            }

            outputURL = produced
            progress = 1
            phase = .finished
            statusText = "完成 · \(formatBytes(FileManager.default.fileSize(at: produced)))"

            if saveToPhotos {
                do {
                    try await MediaSaver.saveVideoToPhotos(produced)
                    savedToPhotos = true
                    statusText = "完成并已保存到相册"
                } catch {
                    errorText = error.localizedDescription
                }
            }

            removeWorkspace()
            onFinish?(self)
        } catch {
            if Task.isCancelled || isCancellation(error) {
                phase = .cancelled
                statusText = "已取消"
                removeWorkspace()
            } else {
                phase = .failed
                errorText = error.localizedDescription
                statusText = "失败"
                // 保留 workspace，重试时可复用已下载分片
            }
            onFinish?(self)
        }
    }

    // MARK: - 分片

    private func downloadSegments(_ segments: [HLSSegment]) async throws {
        let total = segments.count
        var completed = 0
        var index = 0
        let limit = max(1, concurrency)
        let keyCache = keys
        let refererValue = referer

        while index < total {
            try Task.checkCancellation()
            let upper = min(index + limit, total)
            let batch = Array(index..<upper)

            try await withThrowingTaskGroup(of: Int64.self) { group in
                for segmentIndex in batch {
                    let segment = segments[segmentIndex]
                    let destination = workspace.appendingPathComponent(segmentFileName(segmentIndex))
                    group.addTask {
                        try await DownloadJob.downloadOne(
                            segment: segment,
                            referer: refererValue,
                            destination: destination,
                            keys: keyCache
                        )
                    }
                }
                for try await size in group {
                    completed += 1
                    downloadedBytes += size
                    let ratio = Double(completed) / Double(max(1, total))
                    progress = 0.05 + 0.8 * ratio
                    statusText = "分片 \(completed)/\(total) · \(formatBytes(downloadedBytes))"
                }
            }

            index = upper
        }
    }

    private nonisolated static func downloadOne(
        segment: HLSSegment,
        referer: String?,
        destination: URL,
        keys: KeyCache
    ) async throws -> Int64 {
        if FileManager.default.fileExists(atPath: destination.path) {
            return FileManager.default.fileSize(at: destination)
        }

        var lastError: Error = DownloadError.network("未知错误")
        for attempt in 1...3 {
            try Task.checkCancellation()
            do {
                let payload = try await fetchPayload(segment: segment, referer: referer, keys: keys)
                try payload.write(to: destination, options: .atomic)
                return Int64(payload.count)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(250_000_000 * attempt))
                }
            }
        }
        throw lastError
    }

    private nonisolated static func fetchPayload(
        segment: HLSSegment,
        referer: String?,
        keys: KeyCache
    ) async throws -> Data {
        if segment.key?.isSampleAES == true { throw DownloadError.sampleAES }

        let data = try await HLSClient.getData(
            url: segment.url,
            referer: referer,
            range: segment.byteRange
        )

        guard let key = segment.key, key.isAES128 else { return data }
        guard let keyURL = key.uri else { throw DownloadError.badKey }

        let keyData = try await keys.data(for: keyURL, referer: referer)
        let iv = key.iv ?? HLSKey.iv(forSequence: segment.sequence)
        return try Crypto.aes128CBCDecrypt(data, key: keyData, iv: iv)
    }

    private func fetchInitMap(_ playlist: HLSPlaylist) async throws -> URL? {
        guard let map = playlist.segments.first(where: { $0.map != nil })?.map else { return nil }
        let destination = workspace.appendingPathComponent("init.bin")
        if !FileManager.default.fileExists(atPath: destination.path) {
            let data = try await HLSClient.getData(url: map.url, referer: referer, range: map.range)
            try data.write(to: destination, options: .atomic)
        }
        return destination
    }

    // MARK: - 工具

    private func segmentFileName(_ index: Int) -> String {
        String(format: "seg-%06d.bin", index)
    }

    private func removeWorkspace() {
        try? FileManager.default.removeItem(at: workspace)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let downloadError = error as? DownloadError, case .cancelled = downloadError { return true }
        return false
    }

    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "m3u8grab.download") { [weak self] in
            guard let self = self else { return }
            self.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

// MARK: - 持久化

struct JobRecord: Codable {
    var id: UUID
    var title: String
    var sourceURL: String
    var outputPath: String?
    var format: OutputFormat
    var createdAt: Date
    var phase: DownloadPhase
    var duration: Double
}

extension DownloadJob {
    /// 冷启动恢复：输出文件仍在 → 直接标记完成
    func markRestoredFinished(outputPath: String, duration: Double) {
        self.duration = duration
        self.outputURL = URL(fileURLWithPath: outputPath)
        self.phase = .finished
        self.progress = 1
        self.statusText = "完成 · \(formatBytes(FileManager.default.fileSize(at: URL(fileURLWithPath: outputPath))))"
    }

    /// 冷启动恢复：无法继续的任务 → 标记为失败并可重试
    func markRestored(outputPath: String?, duration: Double, phase: DownloadPhase) {
        self.duration = duration
        if let outputPath {
            self.outputURL = URL(fileURLWithPath: outputPath)
        }
        self.phase = phase
        self.progress = 0
        self.statusText = phase == .failed ? "上次未完成，可重试" : "已取消"
    }

    func makeRecord() -> JobRecord {
        JobRecord(
            id: id,
            title: title,
            sourceURL: sourceURL.absoluteString,
            outputPath: outputURL?.path,
            format: format,
            createdAt: createdAt,
            phase: phase,
            duration: duration
        )
    }
}
