import Foundation
import WebKit
import Combine

enum GrabConstants {
    static let messageHandlerName = "m3u8grab"
    static let homeURLString = "https://www.bing.com"
}

/// 内置浏览器引擎：WKWebView + 脚本注入 + 导航状态
@MainActor
final class BrowserEngine: NSObject, ObservableObject {
    @Published var addressText: String = GrabConstants.homeURLString
    @Published private(set) var pageTitle: String = ""
    @Published private(set) var currentURL: URL?
    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published var lastError: String?
    /// 用户直接在地址栏/外部跳进来的 m3u8：提示一键下载
    @Published var interceptedPlaylist: URL?

    let sniffer: Sniffer
    private(set) var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []

    init(sniffer: Sniffer) {
        self.sniffer = sniffer
        super.init()
    }

    // MARK: - WebView 构建

    func webViewInstance() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let controller = WKUserContentController()
        controller.add(self, name: GrabConstants.messageHandlerName)
        if let scriptSource = BrowserEngine.loadInjectedScript() {
            let script = WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            controller.addUserScript(script)
        }
        configuration.userContentController = controller

        let created = WKWebView(frame: .zero, configuration: configuration)
        created.allowsBackForwardNavigationGestures = true
        created.navigationDelegate = self
        created.uiDelegate = self
        created.scrollView.contentInsetAdjustmentBehavior = .automatic
        created.isOpaque = false
        created.backgroundColor = .systemBackground
        // 网页绘制之前的底色跟随深浅色，滚动回弹时不闪白（iOS 15+）
        created.underPageBackgroundColor = .systemBackground

        observations = [
            created.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? 0
                Task { @MainActor in self?.progress = value }
            },
            created.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.isLoading = value }
            },
            created.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.canGoBack = value }
            },
            created.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.canGoForward = value }
            },
            created.observe(\.url, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? nil
                Task { @MainActor in
                    guard let self else { return }
                    self.currentURL = value
                    if let value { self.addressText = value.absoluteString }
                }
            },
            created.observe(\.title, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? nil
                Task { @MainActor in
                    guard let self else { return }
                    let title = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    self.pageTitle = title
                    self.sniffer.currentPageTitle = title.isEmpty ? (self.currentURL?.host ?? "") : title
                }
            }
        ]

        webView = created
        return created
    }

    private static func loadInjectedScript() -> String? {
        if let url = Bundle.main.url(forResource: "injected", withExtension: "js"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        // 兜底：脚本没打进 bundle 时至少保住 fetch/XHR 两条通道
        return """
        (function(){if(window.__m3u8grabInstalled)return;window.__m3u8grabInstalled=true;
        function r(u){try{var a=new URL(u,location.href).href;if(!/\\.m3u8(\\?|#|$)/i.test(a))return;
        window.webkit.messageHandlers.m3u8grab.postMessage({type:'stream',url:a,kind:'hls',pageURL:location.href,pageTitle:document.title||''});}catch(e){}}
        var f=window.fetch;if(f)window.fetch=function(i){try{r(typeof i==='string'?i:(i&&i.url))}catch(e){};return f.apply(this,arguments)};
        var o=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){try{r(u)}catch(e){};return o.apply(this,arguments)};
        })();
        """
    }

    // MARK: - 导航

    func load(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if !text.contains("://") {
            if text.contains(".") && !text.contains(" ") {
                text = "https://" + text
            } else {
                let escaped = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
                text = "https://www.bing.com/search?q=\(escaped)"
            }
        }

        guard let url = URL(string: text) else {
            lastError = "无效地址"
            return
        }
        lastError = nil

        if text.lowercased().contains(".m3u8") {
            interceptedPlaylist = url
        }

        let view = webViewInstance()
        view.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    func goHome() {
        load(GrabConstants.homeURLString)
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stopLoading() { webView?.stopLoading() }

    func clearWebsiteData() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let store = WKWebsiteDataStore.default()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
        sniffer.clear()
    }

    // MARK: - 嗅探辅助

    func notePlaylist(_ url: URL) {
        sniffer.add(
            urlString: url.absoluteString,
            kind: .hls,
            pageURLString: currentURL?.absoluteString,
            pageTitle: pageTitle
        )
    }
}

// MARK: - WKScriptMessageHandler

extension BrowserEngine: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == GrabConstants.messageHandlerName,
              let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak self] in
            self?.sniffer.ingest(message: body)
        }
    }
}

// MARK: - WKNavigationDelegate

extension BrowserEngine: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.isLoading = true
            self?.lastError = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let url = webView.url
        let title = webView.title ?? ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.sniffer.resetForNewPage(url: url, title: title)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url
        let title = webView.title ?? ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoading = false
            self.progress = 1
            self.sniffer.resetForNewPage(url: url, title: title)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let text = error.localizedDescription
        let code = (error as NSError).code
        Task { @MainActor [weak self] in
            self?.isLoading = false
            if code != NSURLErrorCancelled {
                self?.lastError = text
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let text = error.localizedDescription
        let code = (error as NSError).code
        let failingURL = webView.url
        Task { @MainActor [weak self] in
            self?.isLoading = false
            guard code != NSURLErrorCancelled else { return }
            if code == NSURLErrorUnsupportedURL || code == NSURLErrorBadURL
                || code == NSURLErrorCannotOpenFile {
                if let failingURL, failingURL.absoluteString.lowercased().contains(".m3u8") {
                    self?.interceptedPlaylist = failingURL
                    self?.lastError = nil
                    return
                }
                self?.lastError = "该地址无法在浏览器打开，可能不是网页。若是 m3u8 链接请用「手动下载」。"
            } else {
                self?.lastError = text
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationResponse: WKNavigationResponse,
                             decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        let mime = response.mimeType?.lowercased() ?? ""
        let url = response.url

        if mime.contains("mpegurl") || mime.contains("x-mpegurl")
            || (url?.absoluteString.lowercased().contains(".m3u8") ?? false) {
            if let url {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    self.notePlaylist(url)
                    self.interceptedPlaylist = url
                }
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension BrowserEngine: WKUIDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction,
                             windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            let request = navigationAction.request
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let url = request.url {
                    self.addressText = url.absoluteString
                    if url.absoluteString.lowercased().contains(".m3u8") {
                        self.interceptedPlaylist = url
                        self.notePlaylist(url)
                        return
                    }
                }
                self.webView?.load(request)
            }
        }
        return nil
    }
}
