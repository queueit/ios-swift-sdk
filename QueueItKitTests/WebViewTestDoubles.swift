import UIKit
import WebKit
@testable import QueueItKit

// WebKit's dealloc of an object built without its internal state crashes, so the stand-ins are never released.
private nonisolated(unsafe) var immortalStubs: [AnyObject] = []

final class StubFrameInfo: WKFrameInfo {
    private let main: Bool
    init(isMainFrame: Bool = true) {
        self.main = isMainFrame
        super.init()
        immortalStubs.append(self)
    }
    override var isMainFrame: Bool { main }
}

final class StubNavigationAction: WKNavigationAction {
    private let stubRequest: URLRequest
    private let stubFrame: StubFrameInfo
    init(url: String, isMainFrame: Bool = true) {
        self.stubRequest = URLRequest(url: URL(string: url)!)
        self.stubFrame = StubFrameInfo(isMainFrame: isMainFrame)
        super.init()
        immortalStubs.append(self)
    }
    override var request: URLRequest { stubRequest }
    override var targetFrame: WKFrameInfo? { stubFrame }
}

final class ForwardingProxy: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var target: AnyObject?
    init(target: AnyObject?) {
        self.target = target
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        (target as? WKNavigationDelegate)?.webView?(webView, decidePolicyFor: navigationAction, preferences: preferences, decisionHandler: decisionHandler)
    }
}

enum ProxyMode {
    case passNilThrough
    case wrapEverySet
    case stayInstalledOnNil
}

final class RecordingWebView: WKWebView {
    var loadedRequests: [URLRequest] = []
    var loadedHTML: [String] = []
    var stopLoadingCount = 0
    private var proxyMode: ProxyMode?
    private var navigationProxy: ForwardingProxy?
    private var uiProxy: ForwardingProxy?

    init() {
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return nil
    }

    override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
        loadedHTML.append(string)
        return nil
    }

    override func stopLoading() {
        stopLoadingCount += 1
    }

    func wrapDelegates(mode: ProxyMode) {
        autoreleasepool {
            let currentNavigation = super.navigationDelegate
            let currentUI = super.uiDelegate
            proxyMode = mode
            navigationDelegate = currentNavigation
            uiDelegate = currentUI
        }
    }

    override var navigationDelegate: WKNavigationDelegate? {
        get { super.navigationDelegate }
        set {
            guard let proxyMode else { super.navigationDelegate = newValue; return }
            navigationProxy = RecordingWebView.wrap(newValue, existing: navigationProxy, mode: proxyMode)
            super.navigationDelegate = navigationProxy
        }
    }

    override var uiDelegate: WKUIDelegate? {
        get { super.uiDelegate }
        set {
            guard let proxyMode else { super.uiDelegate = newValue; return }
            uiProxy = RecordingWebView.wrap(newValue, existing: uiProxy, mode: proxyMode)
            super.uiDelegate = uiProxy
        }
    }

    private static func wrap(_ target: AnyObject?, existing: ForwardingProxy?, mode: ProxyMode) -> ForwardingProxy? {
        switch mode {
        case .passNilThrough:
            return target.map { ForwardingProxy(target: $0) }
        case .wrapEverySet:
            return ForwardingProxy(target: target)
        case .stayInstalledOnNil:
            guard let existing else { return target.map { ForwardingProxy(target: $0) } }
            if let target { existing.target = target }
            return existing
        }
    }
}

final class StubNavigationResponse: WKNavigationResponse {
    override init() {
        super.init()
        immortalStubs.append(self)
    }
}

final class StubChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

func makeQueueResult(url: String? = "https://customer.queue-it.net/queue?c=c&e=e&q=q", target: String? = nil) -> QueueTryPassResult {
    QueueTryPassResult(queueItToken: "~rt_queue~", queueUrl: url, targetUrl: target, isPassedThrough: false, redirectType: .queue, urlTTLInMinutes: 5)
}

@MainActor
func decision(of manager: QueueItViewManager, for url: String, in webView: WKWebView, isMainFrame: Bool = true) -> WKNavigationActionPolicy? {
    var policy: WKNavigationActionPolicy?
    manager.webView(webView, decidePolicyFor: StubNavigationAction(url: url, isMainFrame: isMainFrame), preferences: WKWebpagePreferences()) { answer, _ in
        policy = answer
    }
    return policy
}

@MainActor
func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

// Returns once work has run on a background queue and the main queue has run everything queued
// before this point, so any main-thread hop work made has happened. No timeout: a starved CI runner
// delays both queues far past any fixed one, while a missing or off-main call still fails at once.
@MainActor
func runInBackgroundThenDrainMainQueue(_ work: @escaping () -> Void) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            work()
            continuation.resume()
        }
    }
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

func tap(_ action: UIAlertAction) {
    typealias Handler = @convention(block) (UIAlertAction) -> Void
    guard let block = action.value(forKey: "handler") else { return }
    unsafeBitCast(block as AnyObject, to: Handler.self)(action)
}
