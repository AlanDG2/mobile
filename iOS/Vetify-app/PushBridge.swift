import Foundation
@preconcurrency import WebKit

/// Estado compartido de push entre AppDelegate (recibe el token y el tap desde APNs)
/// y ViewController (dueño del WKWebView que habla con la web).
final class PushBridge {
    static let shared = PushBridge()
    private init() {}

    static let tokenDidChange = Notification.Name("PushBridge.tokenDidChange")
    static let deepLinkReceived = Notification.Name("PushBridge.deepLinkReceived")

    private(set) var deviceToken: String?
    private var pendingDeepLink: String?

    func updateToken(_ token: String) {
        deviceToken = token
        NotificationCenter.default.post(name: PushBridge.tokenDidChange, object: nil)
    }

    func clearToken() {
        deviceToken = nil
    }

    func receiveDeepLink(_ url: String) {
        pendingDeepLink = url
        NotificationCenter.default.post(name: PushBridge.deepLinkReceived, object: nil)
    }

    /// Devuelve el deep link pendiente (si hay) y lo limpia, para no navegar dos veces.
    func consumePendingDeepLink() -> String? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }
}

/// Proxy débil para registrar un WKScriptMessageHandler sin generar retain cycle
/// (WKUserContentController retiene fuerte a sus handlers).
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
