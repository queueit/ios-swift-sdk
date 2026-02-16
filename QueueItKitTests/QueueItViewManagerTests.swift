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
}
