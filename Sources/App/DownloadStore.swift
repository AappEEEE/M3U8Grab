import Foundation
import Combine

@MainActor
final class DownloadStore: ObservableObject {
    @Published private(set) var jobs: [DownloadJob] = []
    @Published var concurrency: Int = 8 { didSet { persist() } }
    @Published var autoSaveToPhotos: Bool = false { didSet { persist() } }
    @Published var toast: String?

    private let stateURL: URL
    private var persistScheduled = false
    private var jobObservers: [UUID: AnyCancellable] = [:]

    private func observe(_ job: DownloadJob) {
        jobObservers[job.id] = job.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    init() {
        stateURL = Paths.documents.appendingPathComponent("state.json")
        restore()
    }

    @discardableResult
    func startRemote(playlistURL: URL, variantURL: URL? = nil, title: String, referer: String?, format: OutputFormat, saveToPhotos: Bool) -> DownloadJob {
        let job = DownloadJob(title: sanitizeFileName(title), sourceURL: playlistURL, variantURL: variantURL, referer: referer, format: format, saveToPhotos: saveToPhotos || autoSaveToPhotos, concurrency: concurrency)
        enqueue(job)
        return job
    }

    @discardableResult
    func startInline(text: String, baseURL: URL, title: String, format: OutputFormat, saveToPhotos: Bool) -> DownloadJob {
        let job = DownloadJob(title: sanitizeFileName(title), sourceURL: baseURL, inlineText: text, format: format, saveToPhotos: saveToPhotos || autoSaveToPhotos, concurrency: concurrency)
        enqueue(job)
        return job
    }

    private func enqueue(_ job: DownloadJob) {
        job.onFinish = { [weak self] _ in self?.persist() }
        observe(job)
        jobs.insert(job, at: 0)
        persist()
        job.start()
    }

    func cancel(_ job: DownloadJob) { job.cancel(); persist() }
    func pause(_ job: DownloadJob) { job.pause(); persist() }
    func resume(_ job: DownloadJob) { job.resume(); persist() }

    func retry(_ job: DownloadJob) {
        guard !job.isActive else { return }
        if job.phase == .failed || job.phase == .cancelled || job.phase == .paused {
            job.resume()
            persist()
        }
    }

    func remove(_ job: DownloadJob, deleteFile: Bool = true) {
        // 活动任务自行等待在途请求/合并退出后清理，避免删除仍在写入的目录。
        if job.phase != .finished { job.cancel() }
        if deleteFile, let url = job.outputURL { try? FileManager.default.removeItem(at: url) }
        jobs.removeAll { $0.id == job.id }
        jobObservers.removeValue(forKey: job.id)
        persist()
    }

    func clearFinished() {
        for job in jobs.filter({ $0.phase == .finished }) { remove(job, deleteFile: false) }
    }

    func saveToPhotos(_ job: DownloadJob) { job.saveToPhotoLibrary() }
    var activeCount: Int { jobs.filter(\.isActive).count }
    var finishedCount: Int { jobs.filter { $0.phase == .finished }.count }
    /// 所有进行中任务之和，用于列表头部展示总体速度。
    var totalSpeed: Double { jobs.reduce(0) { $0 + ($1.isActive ? $1.currentSpeed : 0) } }
    var resumableCount: Int {
        jobs.filter { $0.phase == .paused || $0.phase == .failed || $0.phase == .cancelled }.count
    }

    func resumeAll() {
        for job in jobs where job.phase == .paused || job.phase == .failed || job.phase == .cancelled { job.resume() }
        persist()
    }

    func pauseAll() {
        for job in jobs where job.canPause { job.pause() }
        persist()
    }

    private struct PersistedState: Codable {
        var concurrency: Int?
        var autoSaveToPhotos: Bool?
        var jobs: [JobRecord]
    }

    private func persist() {
        guard !persistScheduled else { return }
        persistScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.persistScheduled = false
            let state = PersistedState(concurrency: self.concurrency, autoSaveToPhotos: self.autoSaveToPhotos, jobs: self.jobs.map { $0.makeRecord() })
            do {
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(state).write(to: self.stateURL, options: .atomic)
            } catch { }
        }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistedState.self, from: data) else { return }
        if let stored = state.concurrency { concurrency = max(1, min(16, stored)) }
        autoSaveToPhotos = state.autoSaveToPhotos ?? false

        jobs = state.jobs.compactMap { record in
            guard let url = URL(string: record.sourceURL) else { return nil }
            let variant = record.variantURL.flatMap(URL.init(string:))
            let job = DownloadJob(
                id: record.id,
                title: record.title,
                sourceURL: url,
                variantURL: variant,
                inlineText: record.inlineText,
                referer: record.referer,
                format: record.format,
                saveToPhotos: record.saveToPhotos ?? false,
                concurrency: concurrency,
                createdAt: record.createdAt
            )
            job.restoreDownloadState(segmentURLs: record.segmentURLs, retryURLs: record.retryURLs)
            if let path = record.outputPath, FileManager.default.fileExists(atPath: path) {
                job.markRestoredFinished(outputPath: path, duration: record.duration)
            } else {
                let restoredPhase: DownloadPhase = record.phase == .cancelled ? .cancelled : (record.phase == .failed ? .failed : .paused)
                job.markRestored(outputPath: nil, duration: record.duration, phase: restoredPhase)
            }
            job.onFinish = { [weak self] _ in self?.persist() }
            observe(job)
            return job
        }
    }
}
