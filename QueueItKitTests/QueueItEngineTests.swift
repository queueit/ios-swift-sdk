import XCTest
@testable import QueueItKit

class QueueItEngineTests: XCTestCase {
    
    @MainActor
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // makeEngine now takes the listener directly and creates the engine
    @MainActor
    func makeEngine(listener: MockListener) -> QueueItEngine {
        return QueueItEngine(
            customerId: "testcustomer", // Replace with your actual test customerId
            waitingRoomOrAliasId: "testevent", // Replace with your actual test waitingRoomOrAliasId
            queueListener: listener
        )
    }
    
    @MainActor
    func testHandlePassOrDisabled_safetyNet() async {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let token = "safetyNetToken123"
        let result = QueueTryPassResult(
            queueItToken: token,
            queueUrl: nil,
            targetUrl: "https://example.com/target",
            isPassedThrough: true,
            redirectType: .safetyNet,
            urlTTLInMinutes: 60
        )
        
        // When
        engine.handlePassOrDisabled(result: result)
        
        // Then
        XCTAssertTrue(listener.onQueuePassedCalled)
        XCTAssertEqual(listener.lastQueuePassedInfo?.queueItToken, token)
        XCTAssertFalse(listener.onQueueDisabledCalled)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testHandlePassOrDisabled_directLink() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let token = "directLinkToken456"
        let result = QueueTryPassResult(
            queueItToken: token,
            queueUrl: nil,
            targetUrl: "https://example.com/target",
            isPassedThrough: true,
            redirectType: .directLink,
            urlTTLInMinutes: 0
        )
        
        // When
        engine.handlePassOrDisabled(result: result)
        
        // Then
        XCTAssertTrue(listener.onQueuePassedCalled)
        XCTAssertEqual(listener.lastQueuePassedInfo?.queueItToken, token)
        XCTAssertFalse(listener.onQueueDisabledCalled)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testHandlePassOrDisabled_disabled() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let token = "disabledToken789"
        let result = QueueTryPassResult(
            queueItToken: token,
            queueUrl: nil,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .disabled,
            urlTTLInMinutes: nil
        )
        
        // When
        engine.handlePassOrDisabled(result: result)
        
        // Then
        XCTAssertTrue(listener.onQueueDisabledCalled)
        XCTAssertEqual(listener.lastQueueDisabledInfo?.queueItToken, token)
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testHandlePassOrDisabled_afterEvent() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let token = "afterEventToken"
        let result = QueueTryPassResult(
            queueItToken: token,
            queueUrl: nil,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .afterEvent,
            urlTTLInMinutes: nil
        )
        
        // When
        engine.handlePassOrDisabled(result: result)
        
        // Then
        XCTAssertTrue(listener.onQueueDisabledCalled)
        XCTAssertEqual(listener.lastQueueDisabledInfo?.queueItToken, token)
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testHandlePassOrDisabled_idle() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let token: String? = nil // Test with nil token
        let result = QueueTryPassResult(
            queueItToken: token,
            queueUrl: nil,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .idle,
            urlTTLInMinutes: nil
        )
        
        // When
        engine.handlePassOrDisabled(result: result)
        
        // Then
        XCTAssertTrue(listener.onQueueDisabledCalled)
        XCTAssertEqual(listener.lastQueueDisabledInfo?.queueItToken, token)
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testHandlePassOrDisabled_unknownRedirectType() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let result = QueueTryPassResult(
            queueItToken: "unknownToken",
            queueUrl: nil,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .unknown,
            urlTTLInMinutes: nil
        )
        
        // When
        engine.handlePassOrDisabled(result: result)
        
        // Then
        XCTAssertTrue(listener.onErrorCalled)
        XCTAssertEqual(listener.lastError?.code, .invalidResponse)
        XCTAssertEqual(listener.lastErrorMessage, "Missing Queue URL for display")
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertFalse(listener.onQueueDisabledCalled)
    }
    
    // MARK: - handleCheckError Tests
    
    @MainActor
    func testHandleCheckError_noConnection() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let error: QueueError = QueueError(.noConnection)
        let message = "No internet connection detected."
        
        // When
        engine.handleCheckError(error, message: message)
        
        // Then
        XCTAssertTrue(listener.onErrorCalled)
        XCTAssertEqual(listener.lastError?.code, error.code)
        XCTAssertEqual(listener.lastErrorMessage, message)
        XCTAssertFalse(listener.onQueueItUnavailableCalled)
    }
    
    @MainActor
    func testHandleCheckError_queueItUnavailable() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let error: QueueError = QueueError(.queueitUnavailable)
        let message = "Queue-it service is down."
        
        // When
        engine.handleCheckError(error, message: message)
        
        // Then
        XCTAssertTrue(listener.onQueueItUnavailableCalled)
        XCTAssertFalse(listener.onErrorCalled)
        XCTAssertFalse(listener.onQueuePassedCalled)
    }
    
    @MainActor
    func testHandleCheckError_requestInProgress() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let error: QueueError = QueueError(.requestInProgress)
        let message = "A previous request is still running."
        
        // When
        engine.handleCheckError(error, message: message)
        
        // Then
        // No wait(for:), as no fulfill happens on the listener
        XCTAssertFalse(listener.onErrorCalled)
        XCTAssertFalse(listener.onQueueItUnavailableCalled)
    }
    
    @MainActor
    func testHandleCheckError_invalidResponse() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let error: QueueError = QueueError(.invalidResponse)
        let message = "API returned a bad response."
        
        // When
        engine.handleCheckError(error, message: message)
        
        // Then
        XCTAssertTrue(listener.onErrorCalled)
        XCTAssertEqual(listener.lastError?.code, error.code)
        XCTAssertEqual(listener.lastErrorMessage, message)
        XCTAssertFalse(listener.onQueueItUnavailableCalled)
    }
    
    @MainActor
    func testHandleCheckError_apiError() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let error: QueueError = QueueError(.apiError)
        let message = "Generic API failure."
        
        // When
        engine.handleCheckError(error, message: message)
        
        // Then
        XCTAssertTrue(listener.onErrorCalled)
        XCTAssertEqual(listener.lastError?.code, error.code)
        XCTAssertEqual(listener.lastErrorMessage, message)
    }
    
    @MainActor
    func testHandleCheckError_deviceIDError_withNilMessage() {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let error: QueueError = QueueError(.deviceIDError)
        let message: String? = nil
        
        // When
        engine.handleCheckError(error, message: message)
        
        // Then
        XCTAssertTrue(listener.onErrorCalled)
        XCTAssertEqual(listener.lastError?.code, error.code)
        XCTAssertEqual(listener.lastErrorMessage, "An unknown error occurred")
    }
    
    // MARK: - QueueItEngine.showQueue Tests
    
    @MainActor
    func testEngineShowQueue_withPassedThroughResult_callsOnQueuePassed() async {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let passedResult = QueueTryPassResult(
            queueItToken: "~rt_directlink~token456",
            queueUrl: nil, // URL might be nil for passed-through
            targetUrl: "https://example.com/target",
            isPassedThrough: true, // Key condition
            redirectType: .directLink,
            urlTTLInMinutes: 0
        )
        
        // When
        engine.showQueue(queueTryPassResult: passedResult)
        
        // Then
        XCTAssertFalse(listener.onQueueViewWillOpenCalled)
        XCTAssertTrue(listener.onQueuePassedCalled, "onQueuePassed should be called")
        XCTAssertEqual(listener.lastQueuePassedInfo?.queueItToken, passedResult.queueItToken)
        XCTAssertFalse(listener.onQueueDisabledCalled)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testEngineShowQueue_withDisabledResult_callsOnQueueDisabled() async {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let disabledResult = QueueTryPassResult(
            queueItToken: "~rt_disabled~token789",
            queueUrl: nil,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .disabled, // Key condition
            urlTTLInMinutes: nil
        )
        
        // When
        engine.showQueue(queueTryPassResult: disabledResult)
        
        // Then
        XCTAssertFalse(listener.onQueueViewWillOpenCalled)
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertTrue(listener.onQueueDisabledCalled, "onQueueDisabled should be called")
        XCTAssertEqual(listener.lastQueueDisabledInfo?.queueItToken, disabledResult.queueItToken)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testEngineShowQueue_withAfterEventResult_callsOnQueueDisabled() async {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let afterEventResult = QueueTryPassResult(
            queueItToken: "~rt_afterevent~token123",
            queueUrl: nil,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .afterEvent, // Key condition
            urlTTLInMinutes: nil
        )
        
        // When
        engine.showQueue(queueTryPassResult: afterEventResult)
        
        // Then
        XCTAssertFalse(listener.onQueueViewWillOpenCalled)
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertTrue(listener.onQueueDisabledCalled, "onQueueDisabled should be called")
        XCTAssertEqual(listener.lastQueueDisabledInfo?.queueItToken, afterEventResult.queueItToken)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testEngineShowQueue_withIdleResult_callsOnQueueDisabled() async {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        let idleResult = QueueTryPassResult(
            queueItToken: "~rt_idle~token456",
            queueUrl: nil,
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .idle, // Key condition
            urlTTLInMinutes: nil
        )
        
        // When
        engine.showQueue(queueTryPassResult: idleResult)
        
        // Then
        XCTAssertFalse(listener.onQueueViewWillOpenCalled)
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertTrue(listener.onQueueDisabledCalled, "onQueueDisabled should be called")
        XCTAssertEqual(listener.lastQueueDisabledInfo?.queueItToken, idleResult.queueItToken)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testEngineShowQueue_withQueueAndNilUrl_doesNotCallViewManagerAndDoesNotCallListener() async {
        // Given
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        
        // No expectation needed here, as no listener method is expected to be called by Engine's logic
        let queueResult = QueueTryPassResult(
            queueItToken: "~rt_queue~token789",
            queueUrl: nil, // Key condition: nil URL for .queue type
            targetUrl: nil,
            isPassedThrough: false,
            redirectType: .queue,
            urlTTLInMinutes: 5
        )
        
        // When
        engine.showQueue(queueTryPassResult: queueResult)
        
        // Then
        XCTAssertFalse(engine.viewManager.isShowQueueCalled)
        XCTAssertFalse(listener.onQueueViewWillOpenCalled)
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertFalse(listener.onQueueDisabledCalled)
        XCTAssertFalse(listener.onErrorCalled)
    }
    
    @MainActor
    func testEngineShowQueue_withQueueAndValidUrl_callsViewManagerShowQueue() async {
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
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
        engine.showQueue(queueTryPassResult: queueResult)
        
        XCTAssertTrue(engine.viewManager.isShowQueueCalled)
        XCTAssertTrue(listener.onQueueViewWillOpenCalled)
        XCTAssertFalse(listener.onQueuePassedCalled)
        XCTAssertFalse(listener.onQueueDisabledCalled)
        XCTAssertFalse(listener.onErrorCalled) // Error from ViewManager is tested in its own suite
    }
}
