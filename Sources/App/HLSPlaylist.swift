import Foundation

// MARK: - 数据结构

struct HLSByteRange: Equatable {
    var length: Int
    var offset: Int
    var end: Int { offset + max(0, length - 1) }
}

struct HLSKey: Equatable {
    var method: String
    var uri: URL?
    var iv: Data?

    var isNone: Bool { method.uppercased() == "NONE" }
    var isAES128: Bool { method.uppercased() == "AES-128" }
    var isSampleAES: Bool { method.uppercased().hasPrefix("SAMPLE-AES") }

    /// 缺省 IV = 媒体序列号的 128 位大端表示
    static func iv(forSequence sequence: Int) -> Data {
        var data = Data(repeating: 0, count: 16)
        var value = UInt64(UInt(bitPattern: sequence)).bigEndian
        let bytes = withUnsafeBytes(of: &value) { Data($0) }
        data.replaceSubrange(8..<16, with: bytes)
        return data
    }
}

struct HLSInitMap: Equatable {
    var url: URL
    var range: HLSByteRange?
}

struct HLSSegment: Equatable {
    var url: URL
    var duration: Double
    var sequence: Int
    var byteRange: HLSByteRange?
    var key: HLSKey?
    var map: HLSInitMap?
    var title: String?
}

struct HLSVariant: Identifiable, Equatable {
    var url: URL
    var bandwidth: Int?
    var averageBandwidth: Int?
    var resolution: String?
    var codecs: String?
    var frameRate: Double?

    var id: String { url.absoluteString }

    var displayLabel: String {
        let res = resolution ?? "未知"
        if let bandwidth = bandwidth {
            return "\(res) · \(String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000))"
        }
        return res
    }
}

struct HLSPlaylist {
    var url: URL
    var isMaster: Bool = false
    var variants: [HLSVariant] = []
    var segments: [HLSSegment] = []
    var targetDuration: Double = 0
    var playlistType: String?
    var ended: Bool = false

    var isLive: Bool { !ended && !segments.isEmpty }
    var isEncrypted: Bool { segments.contains { !($0.key?.isNone ?? true) } }
    var usesSampleAES: Bool { segments.contains { $0.key?.isSampleAES ?? false } }
    var hasInitMap: Bool { segments.contains { $0.map != nil } }
    var totalDuration: Double { segments.reduce(0) { $0 + $1.duration } }
    var bestVariant: HLSVariant? {
        variants.max { left, right in
            (left.bandwidth ?? 0) < (right.bandwidth ?? 0)
        }
    }
    var sortedVariants: [HLSVariant] {
        variants.sorted { ($0.bandwidth ?? 0) > ($1.bandwidth ?? 0) }
    }
}

// MARK: - 解析器

enum HLSParser {
    enum ParseError: LocalizedError {
        case invalid

        var errorDescription: String? { "播放列表内容无法识别（缺少 #EXTM3U / #EXTINF）" }
    }

    static func parse(text: String, url: URL) throws -> HLSPlaylist {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var playlist = HLSPlaylist(url: url)
        var pendingVariantAttributes: [String: String]?
        var pendingDuration: Double = 0
        var pendingTitle: String?
        var pendingRange: HLSByteRange?
        var currentKey: HLSKey?
        var currentMap: HLSInitMap?
        var mediaSequence = 0
        var nextRangeOffset = 0
        var sawStreamInfo = false
        var sawSegment = false
        var sawEndList = false
        var recognized = false

        for line in lines where !line.isEmpty {
            if line.hasPrefix("#") {
                let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let tag = String(pieces[0]).uppercased()
                let value = pieces.count > 1 ? String(pieces[1]) : ""

                switch tag {
                case "#EXTM3U":
                    recognized = true
                case "#EXT-X-STREAM-INF":
                    recognized = true
                    sawStreamInfo = true
                    pendingVariantAttributes = attributes(value)
                case "#EXTINF":
                    recognized = true
                    let head = value.split(separator: ",").first.map(String.init) ?? ""
                    pendingDuration = Double(head) ?? 0
                    if let commaIndex = value.firstIndex(of: ",") {
                        let title = String(value[value.index(after: commaIndex)...])
                            .trimmingCharacters(in: .whitespaces)
                        pendingTitle = title.isEmpty ? nil : title
                    }
                case "#EXT-X-BYTERANGE":
                    if let range = parseByteRange(value, defaultOffset: nextRangeOffset) {
                        pendingRange = range
                        nextRangeOffset = range.end + 1
                    }
                case "#EXT-X-KEY":
                    let parsed = attributes(value)
                    let method = parsed["METHOD"] ?? "NONE"
                    if method.uppercased() == "NONE" {
                        currentKey = nil
                    } else {
                        let keyURL = parsed["URI"].flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
                        let iv = parsed["IV"].flatMap { hexData($0) }
                        currentKey = HLSKey(method: method, uri: keyURL, iv: iv)
                    }
                case "#EXT-X-MAP":
                    let parsed = attributes(value)
                    if let uriText = parsed["URI"],
                       let mapURL = URL(string: uriText, relativeTo: url)?.absoluteURL {
                        let range = parsed["BYTERANGE"].flatMap { parseByteRange($0, defaultOffset: 0) }
                        currentMap = HLSInitMap(url: mapURL, range: range)
                    }
                case "#EXT-X-MEDIA-SEQUENCE":
                    mediaSequence = Int(value) ?? 0
                case "#EXT-X-TARGETDURATION":
                    playlist.targetDuration = Double(value) ?? 0
                case "#EXT-X-PLAYLIST-TYPE":
                    playlist.playlistType = value
                case "#EXT-X-ENDLIST":
                    sawEndList = true
                default:
                    break
                }
                continue
            }

            // 非 # 开头：URI 行
            guard let absolute = URL(string: line, relativeTo: url)?.absoluteURL else { continue }

            if let variantAttributes = pendingVariantAttributes {
                var variant = HLSVariant(url: absolute)
                variant.bandwidth = variantAttributes["BANDWIDTH"].flatMap { Int($0) }
                variant.averageBandwidth = variantAttributes["AVERAGE-BANDWIDTH"].flatMap { Int($0) }
                variant.resolution = variantAttributes["RESOLUTION"]
                variant.codecs = variantAttributes["CODECS"]
                variant.frameRate = variantAttributes["FRAME-RATE"].flatMap { Double($0) }
                playlist.variants.append(variant)
                pendingVariantAttributes = nil
            } else {
                sawSegment = true
                playlist.segments.append(
                    HLSSegment(
                        url: absolute,
                        duration: pendingDuration,
                        sequence: mediaSequence + playlist.segments.count,
                        byteRange: pendingRange,
                        key: currentKey,
                        map: currentMap,
                        title: pendingTitle
                    )
                )
                pendingDuration = 0
                pendingTitle = nil
                pendingRange = nil
                nextRangeOffset = 0
            }
        }

        guard recognized || sawSegment else { throw ParseError.invalid }

        playlist.isMaster = sawStreamInfo && !sawSegment
        playlist.ended = sawEndList
        return playlist
    }

    static func attributes(_ value: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = ""
        var buffer = ""
        var inQuotes = false
        var expectingValue = false

        func commit() {
            let trimmedKey = key.trimmingCharacters(in: .whitespaces)
            if !trimmedKey.isEmpty {
                result[trimmedKey.uppercased()] = buffer
            }
            key = ""
            buffer = ""
            expectingValue = false
        }

        for character in value {
            if inQuotes {
                if character == "\"" {
                    inQuotes = false
                } else {
                    buffer.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
            case "=":
                expectingValue = true
            case ",":
                commit()
            default:
                if expectingValue {
                    buffer.append(character)
                } else {
                    key.append(character)
                }
            }
        }
        commit()
        return result
    }

    static func parseByteRange(_ value: String, defaultOffset: Int) -> HLSByteRange? {
        let pieces = value.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard let length = Int(pieces[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        var offset = defaultOffset
        if pieces.count > 1, let explicit = Int(pieces[1].trimmingCharacters(in: .whitespaces)) {
            offset = explicit
        }
        return HLSByteRange(length: length, offset: offset)
    }

    static func hexData(_ value: String) -> Data? {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("0x") { text = String(text.dropFirst(2)) }
        guard !text.isEmpty, text.count % 2 == 0 else { return nil }
        var data = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
