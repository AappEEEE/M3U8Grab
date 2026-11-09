import Foundation

/// 轻量 HLS 网络层：统一 UA / Referer / 超时，供下载引擎与解析预览共用。
enum HLSClient {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = 16
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return URLSession(configuration: configuration)
    }()

    static func makeRequest(url: URL, referer: String?, timeout: TimeInterval = 30) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        if let referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
            if let origin = originString(from: referer) {
                request.setValue(origin, forHTTPHeaderField: "Origin")
            }
        }
        return request
    }

    static func originString(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    static func getText(url: URL, referer: String?) async throws -> String {
        let request = makeRequest(url: url, referer: referer)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.http(http.statusCode, url.absoluteString)
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        throw DownloadError.badPlaylist
    }

    static func getData(url: URL, referer: String?, range: HLSByteRange?, timeout: TimeInterval = 30) async throws -> Data {
        var request = makeRequest(url: url, referer: referer, timeout: timeout)
        if let range {
            request.setValue("bytes=\(range.offset)-\(range.end)", forHTTPHeaderField: "Range")
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw DownloadError.http(http.statusCode, url.absoluteString)
            }
            if http.value(forHTTPHeaderField: "Content-Encoding") == nil,
               let declared = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), declared != data.count {
                throw DownloadError.network("响应长度不完整（期望 \(declared)，收到 \(data.count)）")
            }
            if let range {
                guard http.statusCode == 206 else {
                    throw DownloadError.network("服务器未按 Range 返回分片（HTTP \(http.statusCode)）")
                }
                if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
                   !contentRange.lowercased().hasPrefix("bytes \(range.offset)-\(range.end)/") {
                    throw DownloadError.network("Range 响应位置不匹配：\(contentRange)")
                }
                guard data.count == range.length else {
                    throw DownloadError.network("Range 长度不完整（期望 \(range.length)，收到 \(data.count)）")
                }
            }
        }
        guard !data.isEmpty else { throw DownloadError.emptySegment(url.absoluteString) }
        return data
    }
}

/// AES-128 密钥缓存（同一 URI 只取一次）
actor KeyCache {
    private var storage: [String: Data] = [:]

    func data(for url: URL, referer: String?) async throws -> Data {
        let key = url.absoluteString
        if let cached = storage[key] { return cached }
        let raw = try await HLSClient.getData(url: url, referer: referer, range: nil)
        guard raw.count >= 16 else { throw DownloadError.badKey }
        let normalized = raw.count == 16 ? raw : Data(raw.prefix(16))
        storage[key] = normalized
        return normalized
    }

    func reset() {
        storage.removeAll()
    }
}
