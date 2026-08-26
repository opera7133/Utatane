import AppKit
import UtataneRealtime
import WebKit

@MainActor
final class RealtimeVoiceWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var onAssistantTranscript: ((RealtimeTranscriptUpdate) -> Void)?
    var onExpressionChange: ((RealtimeExpression) -> Void)?
    var onError: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let client: RealtimeAPIClient
    private let scriptMessageHandler = WeakScriptMessageHandler()
    private var webView: WKWebView!
    private var pageURL: URL?
    private var activeCallID: String?
    private var isCreatingCall = false
    private var eventInterpreter = RealtimeEventInterpreter()

    init(configuration: RealtimeAPIConfiguration) {
        client = RealtimeAPIClient(configuration: configuration)
        super.init(window: nil)

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        webConfiguration.userContentController.add(scriptMessageHandler, name: "realtime")
        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "リアルタイム音声会話")
        window.contentView = webView
        window.center()
        window.delegate = self
        self.window = window
        scriptMessageHandler.delegate = self
        loadPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "realtime")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "realtime", let payload = message.body as? [String: Any], let type = payload["type"] as? String else {
            return
        }
        switch type {
        case "offer":
            guard let sdp = payload["sdp"] as? String else { return }
            createCall(offerSDP: sdp)
        case "hangup":
            let callID = payload["callID"] as? String ?? activeCallID
            activeCallID = nil
            eventInterpreter.reset()
            onExpressionChange?(.restore)
            if let callID {
                Task { try? await client.hangup(callID: callID) }
            }
        case "event":
            handle(event: payload["event"] as? [String: Any])
        case "error":
            if let message = payload["message"] as? String {
                onError?(message)
            }
        default:
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(url.isFileURL && url.standardizedFileURL == pageURL?.standardizedFileURL ? .allow : .cancel)
    }

    func windowWillClose(_ notification: Notification) {
        webView.evaluateJavaScript("window.utataneRealtime?.stop()")
        eventInterpreter.reset()
        onExpressionChange?(.restore)
        if let activeCallID {
            self.activeCallID = nil
            Task { try? await client.hangup(callID: activeCallID) }
        }
        onClose?()
    }

    private func loadPage() {
        guard let pageURL = Bundle.main.url(forResource: "RealtimeVoice", withExtension: "html") else {
            onError?("Realtime音声会話の画面を読み込めなかった。")
            return
        }
        self.pageURL = pageURL
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }

    private func createCall(offerSDP: String) {
        guard !isCreatingCall else { return }
        isCreatingCall = true
        Task {
            defer { isCreatingCall = false }
            do {
                let call = try await client.createCall(offerSDP: offerSDP)
                activeCallID = call.id
                var payload: [String: Any] = ["sdp": call.answerSDP]
                if let callID = call.id {
                    payload["callID"] = callID
                }
                sendToPage(function: "receiveAnswer", payload: payload)
            } catch {
                sendToPage(function: "receiveError", payload: ["message": error.localizedDescription])
                onError?(error.localizedDescription)
            }
        }
    }

    private func handle(event: [String: Any]?) {
        guard let event, let type = event["type"] as? String else { return }
        if activeCallID == nil, type == "session.created",
           let session = event["session"] as? [String: Any], let id = session["id"] as? String
        {
            activeCallID = id
        }
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let effects = try? eventInterpreter.handle(data: data)
        else { return }
        if let transcript = effects.transcript, transcript.role == .assistant {
            onAssistantTranscript?(transcript)
        }
        if let expression = effects.expression {
            onExpressionChange?(expression)
        }
    }

    private func sendToPage(function: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript("window.utataneRealtime?.\(function)(\(json))")
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
