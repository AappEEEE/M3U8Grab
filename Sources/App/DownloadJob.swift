import Foundation
import Combine
import UIKit

/// 已完成分片以原子文件保存；任务身份和完整播放列表在暂停、失败及重启后保留。
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
    @Published private(set) var statusText = "等待开始"
    @Published private(set) var outputURL: URL?
    @Published private(set) var errorText: String?
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var totalSegments = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var savedToPhotos = false
    @Published private(set) var currentSpeed: Double = 0
    @Published private(set) var etaSeconds: TimeInterval?
    @Published private(set) var isStopping = false

    var onFinish: ((DownloadJob) -> Void)?
    private let keys = KeyCache()
    private var task: Task<Void, Never>?
    private var speedTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let workspace: URL
    private var pauseRequested = false
    private var playlistPlan: HLSPlaylist?
    private var legacySegmentURLs: [String] = []
    private var completedSegments = 0
    private var deferredSegments = 0
    private var retryRound = 0
    private var runBytes: Int64 = 0
    private var speedSamples: [(time: TimeInterval, bytes: Int64)] = []

    init(id: UUID = UUID(), title: String, sourceURL: URL, variantURL: URL? = nil, inlineText: String? = nil, referer: String? = nil, format: OutputFormat = .mp4, saveToPhotos: Bool = false, concurrency: Int = 8, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.variantURL = variantURL
        self.inlineText = inlineText
        self.referer = referer
        self.format = format
        self.saveToPhotos = saveToPhotos
        self.concurrency = max(1, min(concurrency, 16))
        self.createdAt = createdAt
        self.workspace = Paths.workspaces.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    var isActive: Bool { phase.isActive }
    var canPause: Bool { !isStopping && (phase == .queued || phase == .fetching || phase == .downloading) }
    var outputSizeText: String {
        guard let outputURL else { return "" }
        return formatBytes(FileManager.default.fileSize(at: outputURL))
    }
    var speedText: String { "\(formatBytes(Int64(max(0, currentSpeed))))/s" }
    var etaText: String? {
        guard let etaSeconds, etaSeconds.isFinite, etaSeconds >= 0 else { return nil }
        if etaSeconds < 60 { return "约 \(Int(etaSeconds.rounded())) 秒" }
        if etaSeconds < 3600 { return "约 \(Int(etaSeconds / 60)) 分钟" }
        return "约 \(Int(etaSeconds / 3600)) 小时 \(Int(etaSeconds.truncatingRemainder(dividingBy: 3600) / 60)) 分钟"
    }
    /// 下载列表单行摘要：分片进度 · 已下载 · 速度 · 剩余 · 补片状态。
    var metricsText: String {
        guard phase == .downloading || phase == .fetching || phase == .paused || phase == .failed || phase == .merging else {
            return statusText
        }
        var parts: [String] = []
        if totalSegments > 0 { parts.append("\(completedSegments)/\(totalSegments)") }
        if downloadedBytes > 0 { parts.append(formatBytes(downloadedBytes)) }
        if phase == .downloading {
            parts.append(speedText)
            if let etaText { parts.append(etaText) }
        }
        if deferredSegments > 0 { parts.append("待补 \(deferredSegments)") }
        if retryRound > 0 { parts.append("第 \(retryRound)/3 轮") }
        return parts.isEmpty ? statusText : parts.joined(separator: " · ")
    }
    var completedSegmentCount: Int { completedSegments }

    func start() {
        guard task == nil, phase == .queued else { return }
        pauseRequested = false
        isStopping = false
        task = Task { [weak self] in await self?.run() }
    }

    func pause() {
        guard canPause, task != nil else { return }
        pauseRequested = true
        isStopping = true
        statusText = "正在暂停，保留已完成分片…"
        task?.cancel()
    }

    func resume() {
        guard task == nil, !isStopping, phase == .paused || phase == .failed || phase == .cancelled else { return }
        errorText = nil
        phase = .queued
        statusText = "准备恢复已完成分片…"
        start()
    }

    func cancel() {
        guard phase != .finished else { return }
        pauseRequested = false
        if let task {
            isStopping = true
            statusText = "正在取消…"
            task.cancel()
        } else {
            phase = .cancelled
            statusText = "已取消"
            removeWorkspace()
            playlistPlan = nil
            onFinish?(self)
        }
    }

    func saveToPhotoLibrary() {
        guard let outputURL else { return }
        Task {
            do {
                try await MediaSaver.saveVideoToPhotos(outputURL)
                savedToPhotos = true
                statusText = "已保存到相册"
                onFinish?(self)
            } catch { errorText = error.localizedDescription }
        }
    }

    private func run() async {
        beginBackgroundTask()
        defer {
            speedTask?.cancel()
            speedTask = nil
            currentSpeed = 0
            etaSeconds = nil
            endBackgroundTask()
            task = nil
            isStopping = false
            onFinish?(self)
        }
        Paths.createIfNeeded(workspace)
        do {
            try Task.checkCancellation()
            let playlist = try await loadPlaylist()
            totalSegments = playlist.segments.count
            duration = playlist.totalDuration
            try Task.checkCancellation()
            phase = .downloading
            onFinish?(self)
            try await downloadSegments(playlist.segments)
            try Task.checkCancellation()
            speedTask?.cancel()
            speedTask = nil
            currentSpeed = 0
            etaSeconds = nil
            phase = .merging
            progress = 0.88
            statusText = "合并 \(totalSegments) 个分片…"
            onFinish?(self)

            // 最终产物先保存在工作目录，取消或进程退出时不留下半个成品。
            let assembled = try await assemble(playlist)
            try Task.checkCancellation()
            let destination = uniqueFileURL(directory: Paths.downloads, baseName: title, pathExtension: assembled.pathExtension)
            try FileManager.default.moveItem(at: assembled, to: destination)
            outputURL = destination
            progress = 1
            phase = .finished
            statusText = "完成 · \(formatBytes(FileManager.default.fileSize(at: destination)))"
            onFinish?(self)
            if saveToPhotos {
                do {
                    try await MediaSaver.saveVideoToPhotos(destination)
                    savedToPhotos = true
                    statusText = "完成并已保存到相册"
                } catch { errorText = error.localizedDescription }
            }
            removeWorkspace()
        } catch {
            if Task.isCancelled {
                if pauseRequested {
                    phase = .paused
                    statusText = "已暂停 · 已完成分片已保留"
                } else {
                    phase = .cancelled
                    statusText = "已取消"
                    removeWorkspace()
                    playlistPlan = nil
                }
            } else {
                // 包括断网/超时在内的失败均保留目录，点击继续只补缺失片。
                phase = .failed
                errorText = error.localizedDescription
                statusText = "下载未完成 · 可继续，已完成分片已保留"
            }
        }
    }

    private func loadPlaylist() async throws -> HLSPlaylist {
        if let playlistPlan { return playlistPlan }
        let snapshot = workspace.appendingPathComponent("playlist.json")
        if let data = try? Data(contentsOf: snapshot),
           let saved = try? JSONDecoder().decode(HLSPlaylist.self, from: data), !saved.segments.isEmpty {
            playlistPlan = saved
            return saved
        }
        phase = .fetching
        statusText = "获取播放列表…"
        progress = 0.02
        let url = variantURL ?? sourceURL
        let text: String
        if let inlineText { text = inlineText }
        else { text = try await HLSClient.getText(url: url, referer: referer) }
        var playlist = try HLSParser.parse(text: text, url: url)
        if playlist.isMaster {
            guard let best = playlist.bestVariant else { throw DownloadError.emptyPlaylist }
            let mediaText = try await HLSClient.getText(url: best.url, referer: referer)
            playlist = try HLSParser.parse(text: mediaText, url: best.url)
        }
        guard !playlist.segments.isEmpty else { throw DownloadError.emptyPlaylist }
        if playlist.usesSampleAES { throw DownloadError.sampleAES }
        // 兼容曾保存 URL 列表的任务；源列表变化时不复用错位分片。
        if !legacySegmentURLs.isEmpty && legacySegmentURLs != playlist.segments.map({ $0.url.absoluteString }) {
            removeWorkspace()
            Paths.createIfNeeded(workspace)
        }
        try JSONEncoder().encode(playlist).write(to: snapshot, options: .atomic)
        legacySegmentURLs = []
        playlistPlan = playlist
        return playlist
    }

    private func downloadSegments(_ segments: [HLSSegment]) async throws {
        let missing = segments.indices.filter { FileManager.default.fileSize(at: segmentURL($0)) <= 0 }
        completedSegments = segments.count - missing.count
        downloadedBytes = segments.indices.reduce(Int64(0)) { $0 + FileManager.default.fileSize(at: segmentURL($1)) }
        deferredSegments = 0
        retryRound = 0
        runBytes = 0
        speedSamples = [(ProcessInfo.processInfo.systemUptime, 0)]
        updateDownloadStatus()
        guard !missing.isEmpty else { return }
        speedTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard let self else { return }
                self.updateSpeed()
            }
        }
        // 首轮单次 30 秒请求；失败立即排到末尾，不阻塞其余分片。
        var failures = try await downloadPass(missing, segments: segments, workers: concurrency, timeout: 30, attempts: 1)
        for round in 1...3 {
            guard !failures.isEmpty else { break }
            try Task.checkCancellation()
            retryRound = round
            deferredSegments = failures.count
            updateDownloadStatus()
            try await Task.sleep(nanoseconds: UInt64(round) * 1_000_000_000)
            failures = try await downloadPass(failures, segments: segments, workers: max(1, concurrency / 2), timeout: 60, attempts: 2)
        }
        deferredSegments = failures.count
        updateDownloadStatus()
        guard failures.isEmpty else {
            throw DownloadError.network("仍有 \(failures.count) 个分片失败；点击继续只下载缺失分片")
        }
    }

    private func downloadPass(_ indices: [Int], segments: [HLSSegment], workers: Int, timeout: TimeInterval, attempts: Int) async throws -> [Int] {
        var cursor = 0
        var failures: [Int] = []
        let keyCache = keys
        let ref = referer
        let directory = workspace
        // 只保留 workers 个在途 Task；任一任务完成后立即补位，无整批等待。
        return try await withThrowingTaskGroup(of: SegmentResult.self) { group in
            for _ in 0..<min(workers, indices.count) {
                let index = indices[cursor]
                cursor += 1
                group.addTask {
                    try await Self.fetchSegment(index: index, segment: segments[index], directory: directory, referer: ref, keys: keyCache, timeout: timeout, attempts: attempts)
                }
            }
            while let result = try await group.next() {
                try Task.checkCancellation()
                if let bytes = result.bytes {
                    downloadedBytes += bytes
                    runBytes += bytes
                    completedSegments += 1
                    if retryRound > 0 { deferredSegments = max(0, deferredSegments - 1) }
                } else {
                    failures.append(result.index)
                    if retryRound == 0 { deferredSegments = failures.count }
                }
                updateSpeed()
                if completedSegments % 8 == 0 { onFinish?(self) }
                if cursor < indices.count {
                    let index = indices[cursor]
                    cursor += 1
                    group.addTask {
                        try await Self.fetchSegment(index: index, segment: segments[index], directory: directory, referer: ref, keys: keyCache, timeout: timeout, attempts: attempts)
                    }
                }
            }
            return failures
        }
    }

    private struct SegmentResult: Sendable {
        let index: Int
        let bytes: Int64?
    }

    private nonisolated static func fetchSegment(index: Int, segment: HLSSegment, directory: URL, referer: String?, keys: KeyCache, timeout: TimeInterval, attempts: Int) async throws -> SegmentResult {
        let destination = directory.appendingPathComponent(String(format: "seg-%06d.bin", index))
        for attempt in 1...attempts {
            try Task.checkCancellation()
            do {
                let data = try await fetchPayload(segment: segment, referer: referer, keys: keys, timeout: timeout)
                try Task.checkCancellation()
                try data.write(to: destination, options: .atomic)
                return SegmentResult(index: index, bytes: Int64(data.count))
            } catch {
                try Task.checkCancellation()
                if attempt < attempts { try await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000) }
            }
        }
        return SegmentResult(index: index, bytes: nil)
    }

    private nonisolated static func fetchPayload(segment: HLSSegment, referer: String?, keys: KeyCache, timeout: TimeInterval) async throws -> Data {
        let data = try await HLSClient.getData(url: segment.url, referer: referer, range: segment.byteRange, timeout: timeout)
        guard let key = segment.key, key.isAES128 else { return data }
        guard let url = key.uri else { throw DownloadError.badKey }
        let keyData = try await keys.data(for: url, referer: referer)
        return try Crypto.aes128CBCDecrypt(data, key: keyData, iv: key.iv ?? HLSKey.iv(forSequence: segment.sequence))
    }

    private func updateSpeed() {
        let now = ProcessInfo.processInfo.systemUptime
        speedSamples.append((now, runBytes))
        // 保留窗口边缘的一个样本，空闲时也会逐步降到零。
        while speedSamples.count > 2 && speedSamples[1].time <= now - 8 { speedSamples.removeFirst() }
        if let first = speedSamples.first {
            currentSpeed = Double(max(0, runBytes - first.bytes)) / max(1, now - first.time)
        }
        let average = Double(downloadedBytes) / Double(max(1, completedSegments))
        etaSeconds = currentSpeed > 1 ? Double(max(0, totalSegments - completedSegments)) * average / currentSpeed : nil
        if phase == .downloading && !isStopping { updateDownloadStatus() }
    }

    private func updateDownloadStatus() {
        progress = min(0.85, 0.05 + 0.80 * Double(completedSegments) / Double(max(1, totalSegments)))
        let retry = retryRound > 0 ? " · 补片第 \(retryRound)/3 轮" : ""
        let pending = deferredSegments > 0 ? " · 待补 \(deferredSegments)" : ""
        statusText = "\(completedSegments)/\(totalSegments) · \(formatBytes(downloadedBytes))\(pending)\(retry)"
    }

    private func assemble(_ playlist: HLSPlaylist) async throws -> URL {
        let files = playlist.segments.indices.map { segmentURL($0) }
        if playlist.hasInitMap {
            var orderedFiles: [URL] = []
            var previousMap: HLSInitMap?
            for (index, segment) in playlist.segments.enumerated() {
                if let map = segment.map, map != previousMap {
                    let initFile = workspace.appendingPathComponent("init-\(index).bin")
                    if FileManager.default.fileSize(at: initFile) <= 0 {
                        var data = try await HLSClient.getData(url: map.url, referer: referer, range: map.range, timeout: 60)
                        if let key = map.key, key.isAES128 {
                            guard let uri = key.uri, let iv = key.iv else { throw DownloadError.badKey }
                            let keyData = try await keys.data(for: uri, referer: referer)
                            data = try Crypto.aes128CBCDecrypt(data, key: keyData, iv: iv)
                        }
                        try data.write(to: initFile, options: .atomic)
                    }
                    orderedFiles.append(initFile)
                    previousMap = map
                }
                orderedFiles.append(files[index])
            }
            let target = workspace.appendingPathComponent("assembled.mp4")
            let mergeFiles = orderedFiles
            try await Task.detached(priority: .userInitiated) { try FileMerger.merge(files: mergeFiles, into: target) }.value
            return target
        }
        let ts = workspace.appendingPathComponent("assembled.ts")
        try await Task.detached(priority: .userInitiated) { try FileMerger.merge(files: files, into: ts) }.value
        try Task.checkCancellation()
        guard format == .mp4 else { return ts }
        statusText = "无损转封装为 MP4…"
        let mp4 = workspace.appendingPathComponent("assembled.mp4")
        do {
            try await Task.detached(priority: .userInitiated) { try Remuxer.remuxToMP4(input: ts, output: mp4) }.value
            return mp4
        } catch {
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: mp4)
            errorText = "MP4 转封装未成功，已保留完整 TS：\(error.localizedDescription)"
            return ts
        }
    }

    private func segmentURL(_ index: Int) -> URL { workspace.appendingPathComponent(String(format: "seg-%06d.bin", index)) }
    private func removeWorkspace() { try? FileManager.default.removeItem(at: workspace) }
    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "m3u8grab.download") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.canPause { self.pause() }
                self.endBackgroundTask()
            }
        }
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

struct JobRecord: Codable {
    var id: UUID
    var title: String
    var sourceURL: String
    var variantURL: String? = nil
    var inlineText: String? = nil
    var referer: String? = nil
    var segmentURLs: [String]? = nil
    var retryURLs: [String]? = nil
    var saveToPhotos: Bool? = nil
    var outputPath: String?
    var format: OutputFormat
    var createdAt: Date
    var phase: DownloadPhase
    var duration: Double
}

extension DownloadJob {
    func restoreDownloadState(segmentURLs: [String]?, retryURLs: [String]?) {
        // URL-only 历史记录只做校验，AES IV、Range、init map 从完整快照恢复。
        legacySegmentURLs = segmentURLs ?? []
    }
    func markRestoredFinished(outputPath: String, duration: Double) {
        self.duration = duration
        outputURL = URL(fileURLWithPath: outputPath)
        phase = .finished
        progress = 1
        statusText = "完成 · \(formatBytes(FileManager.default.fileSize(at: URL(fileURLWithPath: outputPath))))"
    }
    func markRestored(outputPath: String?, duration: Double, phase: DownloadPhase) {
        self.duration = duration
        self.phase = phase
        if let data = try? Data(contentsOf: workspace.appendingPathComponent("playlist.json")),
           let saved = try? JSONDecoder().decode(HLSPlaylist.self, from: data) {
            playlistPlan = saved
            totalSegments = saved.segments.count
            completedSegments = saved.segments.indices.filter { FileManager.default.fileSize(at: segmentURL($0)) > 0 }.count
            downloadedBytes = saved.segments.indices.reduce(0) { $0 + FileManager.default.fileSize(at: segmentURL($1)) }
            progress = 0.05 + 0.80 * Double(completedSegments) / Double(max(1, totalSegments))
        }
        statusText = completedSegments > 0 ? "已恢复 \(completedSegments)/\(totalSegments) 个分片，点击继续" : "点击继续下载"
    }
    func makeRecord() -> JobRecord {
        JobRecord(id: id, title: title, sourceURL: sourceURL.absoluteString, variantURL: variantURL?.absoluteString, inlineText: inlineText, referer: referer, saveToPhotos: saveToPhotos, outputPath: outputURL?.path, format: format, createdAt: createdAt, phase: phase, duration: duration)
    }
}
