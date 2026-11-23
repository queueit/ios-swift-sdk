import WebKit
import XCTest
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

    @MainActor
    func testGivenCancelledLoad_WhenDidFailProvisionalNavigation_ThenNoErrorReportedAndOtherErrorsStillAre() {
        let webView = RecordingWebView()
        let manager = QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(), webView: webView)

        manager.isLoading = true
        manager.webView(webView, didFailProvisionalNavigation: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))

        XCTAssertFalse(manager.isLoading)
        XCTAssertFalse(listener.onErrorCalled)
        XCTAssertNil(manager.webViewError)

        manager.webView(webView, didFailProvisionalNavigation: nil, withError: NSError(domain: "other", code: NSURLErrorCancelled))
        XCTAssertTrue(listener.onErrorCalled)

        listener.onErrorCalled = false
        manager.webView(webView, didFailProvisionalNavigation: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        XCTAssertEqual(listener.lastError?.code, .noConnection)
    }

    @MainActor
    func testGivenCancelledLoad_WhenDidFail_ThenNoErrorReportedAndOtherErrorsStillAre() {
        let webView = RecordingWebView()
        let manager = QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(), webView: webView)

        manager.isLoading = true
        manager.webView(webView, didFail: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))

        XCTAssertFalse(manager.isLoading)
        XCTAssertFalse(listener.onErrorCalled)
        XCTAssertNil(manager.webViewError)

        manager.webView(webView, didFail: nil, withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        XCTAssertEqual(listener.lastError?.code, .apiError)
        XCTAssertNotNil(manager.webViewError)
    }

    @MainActor
    private func makeShowingManager(queueUrl: String, domain: String? = nil, prefix: String? = nil) -> (QueueItViewManager, RecordingWebView) {
        let webView = RecordingWebView()
        let manager = QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(), webView: webView, waitingRoomDomain: domain, queuePathPrefix: prefix)
        manager.showQueue(makeQueueResult(url: queueUrl))
        return (manager, webView)
    }

    @MainActor
    func testGivenCancelAddress_WhenDecidePolicyFor_ThenOnUserExitedOnceAndPageStillLoadsWithUserId() {
        let cancelPaths = ["/cancel.aspx?c=c", "/cancel/c/e", "/cancel/c/e/q", "/CANCEL/c/e/q"]
        for path in cancelPaths {
            listener = MockListener()
            let (manager, webView) = makeShowingManager(queueUrl: "https://customer.queue-it.net/queue?c=c&e=e&q=q")
            let address = "https://customer.queue-it.net\(path)"

            let first = decision(of: manager, for: address, in: webView)

            XCTAssertEqual(first, .cancel, path)
            XCTAssertEqual(listener.onUserExitedCount, 1, path)
            XCTAssertEqual(webView.loadedRequests.count, 1, path)
            let reloaded = webView.loadedRequests[0].url!.absoluteString
            XCTAssertTrue(reloaded.contains("userId="), path)
            XCTAssertEqual(webView.loadedRequests[0].cachePolicy, .reloadIgnoringLocalCacheData, path)

            let second = decision(of: manager, for: reloaded, in: webView)

            XCTAssertEqual(second, .allow, path)
            XCTAssertEqual(listener.onUserExitedCount, 1, path)
        }
    }

    @MainActor
    func testGivenCancelAddressNeedingNoRewrite_WhenDecidePolicyFor_ThenOnUserExitedOnceAndNavigationAllowed() {
        let (manager, webView) = makeShowingManager(queueUrl: "https://customer.queue-it.net/queue?c=c&e=e&q=q")
        let userId = UserIdManager.getUserId()!

        let policy = decision(of: manager, for: "https://customer.queue-it.net/cancel/c/e/q?userId=\(userId)", in: webView)

        XCTAssertEqual(policy, .allow)
        XCTAssertEqual(listener.onUserExitedCount, 1)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    @MainActor
    func testGivenCancelAddressBehindProxyPrefix_WhenDecidePolicyFor_ThenOnUserExitedOnceAndPageStillLoads() {
        let (manager, webView) = makeShowingManager(queueUrl: "https://queue.mydomain.com/queue/app/enqueue?c=c&e=e&q=q", domain: "queue.mydomain.com", prefix: "queue")

        let policy = decision(of: manager, for: "https://queue.mydomain.com/queue/cancel/c/e/q", in: webView)

        XCTAssertEqual(policy, .cancel)
        XCTAssertEqual(listener.onUserExitedCount, 1)
        XCTAssertEqual(webView.loadedRequests.count, 1)
        XCTAssertTrue(webView.loadedRequests[0].url!.absoluteString.hasPrefix("https://queue.mydomain.com/queue/cancel/c/e/q"))
    }

    @MainActor
    func testGivenOtherQueuePages_WhenDecidePolicyFor_ThenOnUserExitedNotCalled() {
        let (manager, webView) = makeShowingManager(queueUrl: "https://customer.queue-it.net/queue?c=c&e=e&q=q")
        let addresses = [
            "https://customer.queue-it.net/cancel/c/e/cancelqueueid",
            "https://customer.queue-it.net/app/enqueue",
            "https://customer.queue-it.net/exitline.aspx?c=c",
            "https://other.example.com/cancel.aspx"
        ]

        for address in addresses {
            _ = decision(of: manager, for: address, in: webView)
        }

        XCTAssertEqual(listener.onUserExitedCount, 0)
    }

    @MainActor
    func testGivenListenerWithoutOnUserExited_WhenDecidePolicyForCancelAddress_ThenNavigationRoutedWithoutError() {
        let legacy = LegacyListener()
        let webView = RecordingWebView()
        let manager = QueueItViewManager(queueListener: legacy, options: QueueItEngineOptions(), webView: webView)
        manager.showQueue(makeQueueResult())

        let policy = decision(of: manager, for: "https://customer.queue-it.net/cancel.aspx", in: webView)

        XCTAssertEqual(policy, .cancel)
        XCTAssertEqual(webView.loadedRequests.count, 1)
        XCTAssertFalse(legacy.onErrorCalled)
    }

    @MainActor
    func testGivenBackgroundThread_WhenShowQueueWithoutUrl_ThenErrorArrivesOnMainThread() async {
        let manager = QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(), webView: RecordingWebView())

        await runInBackgroundThenDrainMainQueue { manager.showQueue(makeQueueResult(url: nil)) }

        XCTAssertEqual(listener.lastErrorMessage, "Missing Queue URL for display")
        XCTAssertTrue(listener.allCallsOnMainThread)
    }

    @MainActor
    func testGivenBackgroundThread_WhenShowQueueWithUrl_ThenViewWillOpenArrivesOnMainThread() async {
        let manager = QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(), webView: RecordingWebView())

        await runInBackgroundThenDrainMainQueue { manager.showQueue(makeQueueResult()) }

        XCTAssertTrue(listener.onQueueViewWillOpenCalled)
        XCTAssertTrue(listener.allCallsOnMainThread)
    }

    @MainActor
    func testGivenBackgroundThread_WhenHandleBackPress_ThenWebViewClosedArrivesOnMainThread() async {
        let manager = QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(), webView: RecordingWebView())
        manager.showWebView = true

        await runInBackgroundThenDrainMainQueue { manager.handleBackPress() }

        XCTAssertTrue(listener.onWebViewClosedCalled)
        XCTAssertTrue(listener.allCallsOnMainThread)
    }

    @MainActor
    func testGivenBackgroundThread_WhenLoadUrlWithoutQueueUrl_ThenErrorArrivesOnMainThread() async {
        let manager = QueueItViewManager(queueListener: listener, options: QueueItEngineOptions(), webView: RecordingWebView())

        await runInBackgroundThenDrainMainQueue { manager.loadUrl() }

        XCTAssertEqual(listener.lastErrorMessage, "Invalid Queue URL for loading")
        XCTAssertTrue(listener.allCallsOnMainThread)
    }
}

class LegacyListener: QueueListener {
    var onErrorCalled = false

    func onQueuePassed(_ queuePassedInfo: QueuePassedInfo) {}
    func onQueueViewWillOpen() {}
    func onQueueDisabled(_ queueDisabledInfo: QueueDisabledInfo) {}
    func onQueueItUnavailable() {}
    func onError(_ error: QueueError, errorMessage: String) { onErrorCalled = true }
}
