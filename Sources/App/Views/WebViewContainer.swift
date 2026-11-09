import SwiftUI
import WebKit

/// 把 BrowserEngine 里的 WKWebView 塞进 SwiftUI
struct WebViewContainer: UIViewRepresentable {
    let engine: BrowserEngine

    func makeUIView(context: Context) -> WKWebView {
        engine.webViewInstance()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 导航全部由 BrowserEngine 驱动，这里不需要同步状态
    }
}
