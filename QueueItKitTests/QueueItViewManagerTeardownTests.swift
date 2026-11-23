import UIKit
import WebKit
import XCTest
@testable import QueueItKit

@MainActor
final class QueueItViewManagerTeardownTests: XCTestCase {
    private var listener = MockListener()
    private let cancelAddress = "https://customer.queue-it.net/cancel/c/e/q"

    override func setUp() {
        super.setUp()
        listener = MockListener()
    }

    private func makeManager(webView: RecordingWebView? = nil, delayMs: Int = 0) -> QueueItViewManager {
        QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(viewDelayMs: delayMs), webView: webView ?? RecordingWebView())
    }

    private func showAndWaitForLoad(_ manager: QueueItViewManager, target: String? = nil) async {
        manager.showQueue(makeQueueResult(target: target))
        let shown = await waitUntil { manager.showWebView }
        XCTAssertTrue(shown)
    }

    private func attachToWindow(_ webView: WKWebView) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let viewController = UIViewController()
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.addSubview(webView)
        return window
    }

    func testGivenPageShowing_WhenHideQueue_ThenSinkInstalledEmptyPageLoadedAndStateReset() async {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)
        await showAndWaitForLoad(manager)

        manager.hideQueue()

        XCTAssertTrue(webView.navigationDelegate is WebViewSink)
        XCTAssertTrue(webView.uiDelegate is WebViewSink)
        XCTAssertEqual(webView.loadedHTML.count, 1)
        XCTAssertGreaterThanOrEqual(webView.stopLoadingCount, 1)
        XCTAssertEqual(webView.loadedRequests.count, 1)
        XCTAssertFalse(manager.showWebView)
        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.currentWebViewUrl)

        let sink = webView.navigationDelegate
        manager.hideQueue()
        XCTAssertTrue(webView.navigationDelegate === sink)
    }

    func testGivenQueueShownWithDelayedLoadPending_WhenHideQueue_ThenQueuePageNotLoadedAndWebViewStaysHidden() async throws {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView, delayMs: 100)
        manager.showQueue(makeQueueResult())

        manager.hideQueue()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(webView.loadedRequests.isEmpty)
        XCTAssertFalse(manager.showWebView)
        XCTAssertTrue(webView.navigationDelegate is WebViewSink)
    }

    func testGivenHiddenManager_WhenShowQueueAgain_ThenManagerReplacesSinkAndPageLoads() async {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)
        await showAndWaitForLoad(manager)
        manager.hideQueue()
        XCTAssertTrue(webView.navigationDelegate is WebViewSink)

        await showAndWaitForLoad(manager)

        XCTAssertTrue(webView.navigationDelegate === manager)
        XCTAssertTrue(webView.uiDelegate === manager)
        XCTAssertEqual(webView.loadedRequests.count, 2)
    }

    func testGivenBackgroundThread_WhenHideQueue_ThenTeardownRunsOnMainThread() async {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)
        await showAndWaitForLoad(manager)

        await runInBackgroundThenDrainMainQueue { manager.hideQueue() }

        XCTAssertFalse(manager.showWebView)
        XCTAssertTrue(webView.navigationDelegate is WebViewSink)
        XCTAssertEqual(webView.loadedHTML.count, 1)
    }

    func testGivenManagerReleasedWithWebViewKept_WhenDeinit_ThenSinkInstalledDialogAnsweredAndEmptyPageLoaded() async {
        let webView = RecordingWebView()
        let window = attachToWindow(webView)
        var manager: QueueItViewManager? = makeManager(webView: webView)
        await showAndWaitForLoad(manager!)
        var answers: [Bool] = []
        manager!.webView(webView, runJavaScriptConfirmPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { answers.append($0) }

        manager = nil

        XCTAssertTrue(webView.navigationDelegate is WebViewSink)
        XCTAssertTrue(webView.uiDelegate is WebViewSink)
        XCTAssertEqual(answers, [false])
        XCTAssertEqual(webView.loadedHTML.count, 1)
        withExtendedLifetime(window) {}
    }

    func testGivenManagerReleasedOnBackgroundThread_WhenDeinit_ThenTeardownHappensOnMainThread() async {
        let webView = RecordingWebView()
        let window = attachToWindow(webView)
        var manager: QueueItViewManager? = makeManager(webView: webView)
        await showAndWaitForLoad(manager!)
        var answers: [Bool] = []
        manager!.webView(webView, runJavaScriptConfirmPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { answers.append($0) }

        await runInBackgroundThenDrainMainQueue { manager = nil }

        XCTAssertTrue(webView.navigationDelegate is WebViewSink)
        XCTAssertEqual(answers, [false])
        XCTAssertEqual(webView.loadedHTML.count, 1)
        withExtendedLifetime(window) {}
    }

    func testGivenHiddenManager_WhenDeinit_ThenAppDelegatesAndPageKept() async {
        let webView = RecordingWebView()
        var manager: QueueItViewManager? = makeManager(webView: webView)
        await showAndWaitForLoad(manager!)
        manager!.hideQueue()
        let appDelegate = ForwardingProxy(target: nil)
        webView.navigationDelegate = appDelegate
        webView.uiDelegate = appDelegate

        manager = nil

        XCTAssertTrue(webView.navigationDelegate === appDelegate)
        XCTAssertTrue(webView.uiDelegate === appDelegate)
        XCTAssertEqual(webView.loadedHTML.count, 1)
    }

    func testGivenNewerManagerAttachedToSameWebView_WhenOlderHidesOrIsReleased_ThenNewerKeepsDelegatesAndPage() {
        let webView = RecordingWebView()
        var older: QueueItViewManager? = makeManager(webView: webView)
        let newer = makeManager(webView: webView)

        older?.hideQueue()
        older = nil

        XCTAssertTrue(webView.navigationDelegate === newer)
        XCTAssertTrue(webView.uiDelegate === newer)
        XCTAssertTrue(webView.loadedHTML.isEmpty)
        XCTAssertEqual(webView.stopLoadingCount, 0)
    }

    func testGivenHideQueueInsideOnUserExited_WhenDecidePolicyForRewrittenCancelAddress_ThenCancelAndNoReload() {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)
        listener.onUserExitedAction = { manager.hideQueue() }
        manager.showQueue(makeQueueResult())

        let policy = decision(of: manager, for: cancelAddress, in: webView)

        XCTAssertEqual(policy, .cancel)
        XCTAssertEqual(listener.onUserExitedCount, 1)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testGivenHideQueueInsideOnUserExited_WhenDecidePolicyForCancelAddressNeedingNoRewrite_ThenCancel() {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)
        listener.onUserExitedAction = { manager.hideQueue() }
        manager.showQueue(makeQueueResult())

        let policy = decision(of: manager, for: "\(cancelAddress)?userId=\(UserIdManager.getUserId()!)", in: webView)

        XCTAssertEqual(policy, .cancel)
        XCTAssertEqual(listener.onUserExitedCount, 1)
    }

    func testGivenHideQueueInsideOnQueueUrlChanged_WhenDecidePolicyForRewrittenAddress_ThenCancelAndNoReload() {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)
        listener.onQueueUrlChangedAction = { manager.hideQueue() }
        manager.showQueue(makeQueueResult())

        let policy = decision(of: manager, for: "https://customer.queue-it.net/app/leaveLine", in: webView)

        XCTAssertEqual(policy, .cancel)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testGivenTornDownManager_WhenDecidePolicyFor_ThenCancelsExceptMainFrameAboutBlank() {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)
        manager.showQueue(makeQueueResult())
        XCTAssertEqual(decision(of: manager, for: "about:blank", in: webView), .allow)

        manager.hideQueue()

        XCTAssertEqual(decision(of: manager, for: "about:blank", in: webView), .allow)
        XCTAssertEqual(decision(of: manager, for: "https://customer.queue-it.net/app/page", in: webView), .cancel)
        XCTAssertEqual(decision(of: manager, for: "https://customer.queue-it.net/app/page", in: webView, isMainFrame: false), .cancel)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testGivenSubframeAboutBlank_WhenDecidePolicyFor_ThenAllowed() {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)

        XCTAssertEqual(decision(of: manager, for: "about:blank", in: webView, isMainFrame: false), .allow)
    }

    func testGivenSink_WhenRequestsArrive_ThenEachIsAnsweredAtOnceWithNilDelegateDefaults() {
        let sink = WebViewSink()
        let webView = RecordingWebView()
        let action = StubNavigationAction(url: "https://example.com")

        var policy: WKNavigationActionPolicy?
        sink.webView(webView, decidePolicyFor: action) { policy = $0 }
        XCTAssertEqual(policy, .allow)

        policy = nil
        let preferences = WKWebpagePreferences()
        var returnedPreferences: WKWebpagePreferences?
        sink.webView(webView, decidePolicyFor: action, preferences: preferences) { policy = $0; returnedPreferences = $1 }
        XCTAssertEqual(policy, .allow)
        XCTAssertTrue(returnedPreferences === preferences)

        var responsePolicy: WKNavigationResponsePolicy?
        sink.webView(webView, decidePolicyFor: StubNavigationResponse()) { responsePolicy = $0 }
        XCTAssertEqual(responsePolicy, .allow)

        let challenge = URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(host: "example.com", port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust),
            proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: StubChallengeSender())
        var disposition: URLSession.AuthChallengeDisposition?
        sink.webView(webView, didReceive: challenge) { disposition = $0; XCTAssertNil($1) }
        XCTAssertEqual(disposition, .performDefaultHandling)

        var alertAnswered = 0
        sink.webView(webView, runJavaScriptAlertPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { alertAnswered += 1 }
        XCTAssertEqual(alertAnswered, 1)

        var confirmAnswer: Bool?
        sink.webView(webView, runJavaScriptConfirmPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { confirmAnswer = $0 }
        XCTAssertEqual(confirmAnswer, false)

        var promptAnswered = false
        var promptAnswer: String? = "unset"
        sink.webView(webView, runJavaScriptTextInputPanelWithPrompt: "p", defaultText: "d", initiatedByFrame: StubFrameInfo()) { promptAnswer = $0; promptAnswered = true }
        XCTAssertTrue(promptAnswered)
        XCTAssertNil(promptAnswer)

        let created = sink.webView(webView, createWebViewWith: WKWebViewConfiguration(), for: action, windowFeatures: WKWindowFeatures())
        XCTAssertNil(created)
    }

    func testGivenConfirmUnanswered_WhenHideQueue_ThenAnsweredFalseOnceAndLaterTapDoesNothing() async {
        let webView = RecordingWebView()
        let window = attachToWindow(webView)
        let manager = makeManager(webView: webView)
        await showAndWaitForLoad(manager)
        var answers: [Bool] = []
        manager.webView(webView, runJavaScriptConfirmPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { answers.append($0) }
        let alert = manager.pendingDialogs.last?.alert
        XCTAssertNotNil(alert)

        manager.hideQueue()
        XCTAssertEqual(answers, [false])
        alert?.actions.forEach(tap)

        XCTAssertEqual(answers, [false])
        withExtendedLifetime(window) {}
    }

    func testGivenConfirmAnsweredByVisitor_WhenHideQueue_ThenNoSecondAnswer() async {
        let webView = RecordingWebView()
        let window = attachToWindow(webView)
        let manager = makeManager(webView: webView)
        await showAndWaitForLoad(manager)
        var answers: [Bool] = []
        manager.webView(webView, runJavaScriptConfirmPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { answers.append($0) }
        let okAction = manager.pendingDialogs.last?.alert?.actions.first { $0.style == .default }

        okAction.map(tap)
        manager.hideQueue()

        XCTAssertEqual(answers, [true])
        withExtendedLifetime(window) {}
    }

    func testGivenPromptUnanswered_WhenHideQueue_ThenAnsweredNilOnce() async {
        let webView = RecordingWebView()
        let window = attachToWindow(webView)
        let manager = makeManager(webView: webView)
        await showAndWaitForLoad(manager)
        var promptAnswers: [String?] = []
        manager.webView(webView, runJavaScriptTextInputPanelWithPrompt: "p", defaultText: "d", initiatedByFrame: StubFrameInfo()) { promptAnswers.append($0) }
        XCTAssertTrue(promptAnswers.isEmpty)

        manager.hideQueue()
        manager.hideQueue()

        XCTAssertEqual(promptAnswers.count, 1)
        XCTAssertNil(promptAnswers[0])
        withExtendedLifetime(window) {}
    }

    func testGivenAlertUnanswered_WhenHideQueue_ThenItsOneCallHappensOnce() async {
        let webView = RecordingWebView()
        let window = attachToWindow(webView)
        let manager = makeManager(webView: webView)
        await showAndWaitForLoad(manager)
        var alertAnswers = 0
        manager.webView(webView, runJavaScriptAlertPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { alertAnswers += 1 }
        XCTAssertEqual(alertAnswers, 0)

        manager.hideQueue()
        manager.hideQueue()

        XCTAssertEqual(alertAnswers, 1)
        withExtendedLifetime(window) {}
    }

    func testGivenScreenCannotPresent_WhenRunJavaScriptConfirmPanel_ThenAnsweredAtOnce() async {
        let webView = RecordingWebView()
        let window = attachToWindow(webView)
        let manager = makeManager(webView: webView)
        await showAndWaitForLoad(manager)
        var answers: [Bool] = []
        window.rootViewController?.present(UIAlertController(title: nil, message: "other", preferredStyle: .alert), animated: false)

        manager.webView(webView, runJavaScriptConfirmPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { answers.append($0) }

        XCTAssertEqual(answers, [false])
        manager.hideQueue()
        XCTAssertEqual(answers, [false])
        withExtendedLifetime(window) {}
    }

    func testGivenViewControllerOutsideWindow_WhenRunJavaScriptConfirmPanel_ThenAnsweredAtOnce() {
        let webView = RecordingWebView()
        let viewController = UIViewController()
        viewController.view.addSubview(webView)
        let manager = makeManager(webView: webView)
        var answers: [Bool] = []

        manager.webView(webView, runJavaScriptConfirmPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { answers.append($0) }

        XCTAssertEqual(answers, [false])
        withExtendedLifetime(viewController) {}
    }

    func testGivenNoScreenToPresentOn_WhenPageDialogsArrive_ThenEachIsAnsweredAtOnce() {
        let webView = RecordingWebView()
        let manager = makeManager(webView: webView)
        var confirmAnswers: [Bool] = []
        var promptAnswers: [String?] = []
        var alertAnswers = 0

        manager.webView(webView, runJavaScriptConfirmPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { confirmAnswers.append($0) }
        manager.webView(webView, runJavaScriptTextInputPanelWithPrompt: "p", defaultText: nil, initiatedByFrame: StubFrameInfo()) { promptAnswers.append($0) }
        manager.webView(webView, runJavaScriptAlertPanelWithMessage: "m", initiatedByFrame: StubFrameInfo()) { alertAnswers += 1 }
        manager.hideQueue()

        XCTAssertEqual(confirmAnswers, [false])
        XCTAssertEqual(promptAnswers.count, 1)
        XCTAssertNil(promptAnswers[0])
        XCTAssertEqual(alertAnswers, 1)
    }
}
