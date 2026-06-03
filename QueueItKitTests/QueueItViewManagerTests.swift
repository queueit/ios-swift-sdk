import XCTest
import WebKit
@testable import QueueItKit

class QueueItViewManagerTests: XCTestCase {
    
    var listener: MockListener = MockListener()
    var viewManager: QueueItViewManager?
    
    @MainActor
    override func setUp() {
        super.setUp()
        listener = MockListener()
        let options = QueueItEngineOptions()
        viewManager = QueueItViewManager(queueListener: listener, options: options, webView: nil)
    }
    
    override func tearDown() {
        super.tearDown()
        viewManager = nil
    }
    
    @MainActor
    func testViewManagerShowQueue_withQueueAndValidUrl() async {
        // Given
        let queueUrl = "https://example.queue-it.net/queue"
        let queueResult = QueueTryPassResult(
            queueItToken: "~rt_queue~token123",
            queueUrl: queueUrl,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .queue,
            urlTTLInMinutes: 5
        )
        
        // When
        viewManager?.showQueue(queueResult)
        
        XCTAssertTrue(listener.onQueueViewWillOpenCalled)
        XCTAssertFalse(listener.onErrorCalled) // Error from ViewManager is tested in its own suite
    }
    
    @MainActor
    func testViewManagerShowQueue_withoutQueueUrl() async {
        // Given
        let queueResult = QueueTryPassResult(
            queueItToken: "~rt_queue~token123",
            queueUrl: nil,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .queue,
            urlTTLInMinutes: 5
        )
        
        // When
        viewManager?.showQueue(queueResult)
        
        XCTAssertFalse(listener.onQueueViewWillOpenCalled)
        XCTAssertTrue(listener.onErrorCalled) // Error from ViewManager is tested in its own suite
    }
    
    @MainActor
    func test_showQueue_respectsViewDelayMs() async {
        // Given: set a small delay for test
        var options = QueueItEngineOptions()
        options.viewDelayMs = 100 // 0.1s
        viewManager = QueueItViewManager(queueListener: listener, options: options, webView: nil)

        let queueResult = QueueTryPassResult(
            queueItToken: "~rt_queue~token123",
            queueUrl: "https://example.queue-it.net/queue",
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .queue,
            urlTTLInMinutes: 5
        )

        // Expectation: showWebView flips to true after delay
        let expect = expectation(description: "showWebView becomes true after delay")

        // When
        viewManager?.showQueue(queueResult)

        // Observe state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { // slightly > 0.1s
            if self.viewManager?.showWebView == true {
                expect.fulfill()
            }
        }

        // Then
        await fulfillment(of: [expect], timeout: 3.0)
        XCTAssertTrue(listener.onQueueViewWillOpenCalled)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    // MARK: - Behind Proxy Tests
    
    @MainActor
    func testViewManagerInitialization_WithBehindProxyParameters() async {
        // Given
        let options = QueueItEngineOptions()
        let waitingRoomDomain = "queue.mydomain.com"
        let queuePathPrefix = "queue"
        
        // When
        let viewManagerWithProxy = QueueItViewManager(
            queueListener: listener,
            options: options,
            webView: nil,
            waitingRoomDomain: waitingRoomDomain,
            queuePathPrefix: queuePathPrefix
        )
        
        // Then
        XCTAssertNotNil(viewManagerWithProxy)
        XCTAssertNotNil(viewManagerWithProxy.webView)
    }
    
    @MainActor
    func testViewManagerInitialization_WithoutBehindProxyParameters() async {
        // Given
        let options = QueueItEngineOptions()
        
        // When
        let viewManagerWithoutProxy = QueueItViewManager(
            queueListener: listener,
            options: options,
            webView: nil
        )
        
        // Then
        XCTAssertNotNil(viewManagerWithoutProxy)
        XCTAssertNotNil(viewManagerWithoutProxy.webView)
    }
    
    @MainActor
    func testViewManagerInitialization_WithOnlyWaitingRoomDomain() async {
        // Given
        let options = QueueItEngineOptions()
        let waitingRoomDomain = "queue.mydomain.com"

        // When
        let viewManagerWithProxy = QueueItViewManager(
            queueListener: listener,
            options: options,
            webView: nil,
            waitingRoomDomain: waitingRoomDomain
        )

        // Then
        XCTAssertNotNil(viewManagerWithProxy)
        XCTAssertNotNil(viewManagerWithProxy.webView)
    }

    // MARK: - onQueuePassed dedupe

    /// Three consecutive `.passed` navigation intercepts during a single queue
    /// presentation should result in exactly one `onQueuePassed` callback to the
    /// listener. Reproduces the case where WKWebView's queue-exit redirect chain
    /// hits decidePolicyFor multiple times before hideQueue's about:blank load
    /// suppresses further navigations.
    @MainActor
    func test_decidePolicyFor_passed_firesListenerOnceAcrossMultipleIntercepts() async {
        // Given a viewManager configured with a known target URL so the URI
        // overrider classifies <targetUrl>?queueittoken=... as `.passed`.
        let targetUrl = "https://shop.example.com/checkout"
        let queueResult = QueueTryPassResult(
            queueItToken: "~rt_queue~initialToken",
            queueUrl: "https://example.queue-it.net/queue",
            targetUrl: targetUrl,
            isPassedThrough: false,
            redirectType: .queue,
            urlTTLInMinutes: 5
        )
        viewManager?.showQueue(queueResult)

        // When three queue-exit navigations arrive in sequence, each carrying a
        // fresh queueittoken (mimicking the live SDK's behavior where every
        // redirect step yields a regenerated token).
        let tokens = [
            "e_test~ts_1~q_abc~rt_queue~h_aaa",
            "e_test~ts_2~q_abc~rt_queue~h_bbb",
            "e_test~ts_3~q_abc~rt_queue~h_ccc"
        ]
        // The delegate method ignores the first arg beyond identity; a throwaway
        // WKWebView keeps the test independent of viewManager's own webView property.
        let stubWebView = WKWebView()
        for token in tokens {
            guard let url = URL(string: "\(targetUrl)?queueittoken=\(token)") else {
                XCTFail("Could not construct test URL")
                return
            }
            let action = StubMainFrameNavigationAction(url: url)
            let expect = expectation(description: "decisionHandler called for \(token)")
            viewManager?.webView(
                stubWebView,
                decidePolicyFor: action,
                preferences: WKWebpagePreferences()
            ) { _, _ in
                expect.fulfill()
            }
            await fulfillment(of: [expect], timeout: 1.0)
        }

        // Then the listener was called exactly once and remembers the token
        // from the *first* intercept (subsequent ones are suppressed).
        XCTAssertEqual(listener.onQueuePassedCallCount, 1,
                       "Expected onQueuePassed to fire once across multiple .passed intercepts")
        XCTAssertEqual(listener.lastQueuePassedInfo?.queueItToken, tokens.first)
    }
}

// MARK: - Test doubles

/// Minimal WKNavigationAction stub that supplies a request URL and reports the
/// target frame as the main frame so the ViewManager's intercept logic runs.
private final class StubMainFrameNavigationAction: WKNavigationAction {
    private let stubRequest: URLRequest
    private let stubFrame: StubMainFrame

    init(url: URL) {
        self.stubRequest = URLRequest(url: url)
        self.stubFrame = StubMainFrame()
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var targetFrame: WKFrameInfo? { stubFrame }
}

private final class StubMainFrame: WKFrameInfo {
    override var isMainFrame: Bool { true }
}

