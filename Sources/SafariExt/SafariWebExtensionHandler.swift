import SafariServices
import Foundation

/// Safari Web Extension 的原生消息处理端。
/// 嗅探与去重都在 JS 侧完成（background.js），这里只做「心跳 / 版本」应答，
/// 保证 appex 有合法的 NSExtensionPrincipalClass，同时给页面脚本一个可选的原生回执。
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]

        var reply: [String: Any] = [
            "ok": true,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]

        if let dict = message as? [String: Any], let action = dict["action"] as? String {
            switch action {
            case "ping":
                reply["message"] = "pong"
            case "count":
                if let count = dict["count"] as? Int {
                    reply["count"] = count
                    UserDefaults.standard.set(count, forKey: "lastSniffedCount")
                }
            default:
                reply["message"] = "unsupported action"
            }
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
