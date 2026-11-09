import Foundation
import AVFoundation
import CoreMedia

/// 分片直拼（原始字节按顺序写入）
enum FileMerger {
    enum MergerError: LocalizedError {
        case cannotCreateOutput

        var errorDescription: String? { "无法创建输出文件（存储空间不足？）" }
    }

    static func merge(files: [URL], into output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw MergerError.cannotCreateOutput
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }

        for file in files {
            // 缺片应阻止交付，而不是静默跳过生成损坏的视频。
            let input = try FileHandle(forReadingFrom: file)
            while true {
                let chunk = try input.read(upToCount: 1 << 20) ?? Data()
                if chunk.isEmpty { break }
                try handle.write(contentsOf: chunk)
            }
            try? input.close()
        }
    }
}

/// MPEG-TS → MP4 无损转封装（读压缩样本、写压缩样本，不重新编码）
enum Remuxer {
    enum RemuxError: LocalizedError {
        case readerFailed(String)
        case writerFailed(String)
        case noTracks

        var errorDescription: String? {
            switch self {
            case let .readerFailed(message): return "读取失败：\(message)"
            case let .writerFailed(message): return "写入失败：\(message)"
            case .noTracks: return "文件里没有可用的音视频轨道"
            }
        }
    }

    static func remuxToMP4(input: URL, output: URL) throws {
        try? FileManager.default.removeItem(at: output)

        let asset = AVURLAsset(url: input, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let tracks = asset.tracks
        guard !tracks.isEmpty else { throw RemuxError.noTracks }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw RemuxError.readerFailed(error.localizedDescription)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        } catch {
            throw RemuxError.writerFailed(error.localizedDescription)
        }

        writer.shouldOptimizeForNetworkUse = true

        var pairs: [(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)] = []
        for track in tracks {
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            readerOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(readerOutput) else { continue }
            reader.add(readerOutput)

            let formatHint: CMFormatDescription
            if let first = track.formatDescriptions.first {
                formatHint = first as! CMFormatDescription
            } else {
                continue
            }

            let writerInput = AVAssetWriterInput(
                mediaType: track.mediaType,
                outputSettings: nil,
                sourceFormatHint: formatHint
            )
            writerInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(writerInput) else { continue }
            writer.add(writerInput)
            pairs.append((readerOutput, writerInput))
        }

        guard !pairs.isEmpty else { throw RemuxError.noTracks }

        guard writer.startWriting() else {
            throw RemuxError.writerFailed(writer.error?.localizedDescription ?? "startWriting 失败")
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw RemuxError.readerFailed(reader.error?.localizedDescription ?? "startReading 失败")
        }

        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.m3u8grab.remux", qos: .userInitiated)
        let group = DispatchGroup()

        for pair in pairs {
            let readerOutput = pair.output
            let writerInput = pair.input
            let latch = OnceLatch()
            group.enter()
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard let buffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        if latch.close() { group.leave() }
                        return
                    }
                    if !writerInput.append(buffer) {
                        writerInput.markAsFinished()
                        if latch.close() { group.leave() }
                        return
                    }
                }
            }
        }

        if group.wait(timeout: .now() + 1800) == .timedOut {
            reader.cancelReading()
            writer.cancelWriting()
            throw RemuxError.writerFailed("超时")
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw RemuxError.readerFailed(reader.error?.localizedDescription ?? "读取中断")
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 900)

        guard writer.status == .completed else {
            throw RemuxError.writerFailed(writer.error?.localizedDescription ?? "最终状态 \(writer.status.rawValue)")
        }
    }
}

/// 保证 group.leave() 只执行一次
private final class OnceLatch {
    private let lock = NSLock()
    private var closed = false

    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        closed = true
        return true
    }
}
