import Foundation

/// 轻量 HLS 网络层：统一 UA / Referer / 超时，供下载引擎与解析预览共用。
enum HLSClient {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = 8
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

    static func getData(url: URL, referer: String?, range: HLSByteRange?) async throws -> Data {
        var request = makeRequest(url: url, referer: referer)
        if let range {
            request.setValue("bytes=\(range.offset)-\(range.end)", forHTTPHeaderField: "Range")
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.http(http.statusCode, url.absoluteString)
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
