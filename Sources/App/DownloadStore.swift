import Foundation
import Combine

@MainActor
final class DownloadStore: ObservableObject {
    @Published private(set) var jobs: [DownloadJob] = []
    @Published var concurrency: Int = 6 {
        didSet { persist() }
    }
    @Published var autoSaveToPhotos: Bool = false {
        didSet { persist() }
    }
    @Published var toast: String?

    private let stateURL: URL

    init() {
        stateURL = Paths.documents.appendingPathComponent("state.json")
        restore()
    }

    // MARK: - 创建任务

    @discardableResult
    func startRemote(
        playlistURL: URL,
        variantURL: URL? = nil,
        title: String,
        referer: String?,
        format: OutputFormat,
        saveToPhotos: Bool
    ) -> DownloadJob {
        let job = DownloadJob(
            title: sanitizeFileName(title),
            sourceURL: playlistURL,
            variantURL: variantURL,
            referer: referer,
            format: format,
            saveToPhotos: saveToPhotos || autoSaveToPhotos,
            concurrency: concurrency
        )
        enqueue(job)
        return job
    }

    @discardableResult
    func startInline(
        text: String,
        baseURL: URL,
        title: String,
        format: OutputFormat,
        saveToPhotos: Bool
    ) -> DownloadJob {
        let job = DownloadJob(
            title: sanitizeFileName(title),
            sourceURL: baseURL,
            inlineText: text,
            format: format,
            saveToPhotos: saveToPhotos || autoSaveToPhotos,
            concurrency: concurrency
        )
        enqueue(job)
        return job
    }

    private func enqueue(_ job: DownloadJob) {
        job.onFinish = { [weak self] _ in
            self?.persist()
        }
        jobs.insert(job, at: 0)
        persist()
        job.start()
    }

    // MARK: - 操作

    func cancel(_ job: DownloadJob) {
        job.cancel()
        persist()
    }

    func retry(_ job: DownloadJob) {
        guard !job.isActive else { return }
        if job.phase == .failed || job.phase == .cancelled {
            // 复用同一份记录，重新入队一个新任务
            let replacement = DownloadJob(
                title: job.title,
                sourceURL: job.sourceURL,
                variantURL: job.variantURL,
                inlineText: job.inlineText,
                referer: job.referer,
                format: job.format,
                saveToPhotos: job.saveToPhotos,
                concurrency: concurrency
            )
            remove(job, deleteFile: false)
            enqueue(replacement)
        }
    }

    func remove(_ job: DownloadJob, deleteFile: Bool = true) {
        if job.isActive { job.cancel() }
        if deleteFile, let url = job.outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        jobs.removeAll { $0.id == job.id }
        try? FileManager.default.removeItem(
            at: Paths.workspaces.appendingPathComponent(job.id.uuidString, isDirectory: true)
        )
        persist()
    }

    func clearFinished() {
        let finished = jobs.filter { $0.phase == .finished || $0.phase == .failed || $0.phase == .cancelled }
        for job in finished {
            remove(job, deleteFile: false)
        }
    }

    func saveToPhotos(_ job: DownloadJob) {
        job.saveToPhotoLibrary()
    }

    var activeCount: Int {
        jobs.filter { $0.isActive }.count
    }

    var finishedCount: Int {
        jobs.filter { $0.phase == .finished }.count
    }

    // MARK: - 持久化

    private struct PersistedState: Codable {
        var concurrency: Int?
        var autoSaveToPhotos: Bool?
        var jobs: [JobRecord]
    }

    private func persist() {
        let state = PersistedState(
            concurrency: concurrency,
            autoSaveToPhotos: autoSaveToPhotos,
            jobs: jobs.map { $0.makeRecord() }
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            // 持久化失败不影响主流程
        }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistedState.self, from: data) else { return }

        if let stored = state.concurrency { concurrency = stored }
        autoSaveToPhotos = state.autoSaveToPhotos ?? false

        var restored: [DownloadJob] = []
        for record in state.jobs {
            guard let url = URL(string: record.sourceURL) else { continue }
            let job = DownloadJob(
                id: record.id,
                title: record.title,
                sourceURL: url,
                format: record.format,
                concurrency: concurrency
            )
            if let path = record.outputPath, FileManager.default.fileExists(atPath: path) {
                job.markRestoredFinished(outputPath: path, duration: record.duration)
            } else if record.phase == .finished {
                job.markRestored(outputPath: nil, duration: record.duration, phase: .failed)
            } else {
                job.markRestored(outputPath: nil, duration: record.duration, phase: .failed)
            }
            restored.append(job)
        }
        jobs = restored
    }
}
