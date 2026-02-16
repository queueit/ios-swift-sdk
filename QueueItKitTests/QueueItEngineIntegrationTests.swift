import XCTest
@testable import QueueItKit

class QueueItEngineIntegrationTests: XCTestCase {
    
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
    func testGetSdkVersion() {
        let listener = MockListener()
        let engine = makeEngine(listener: listener)
        XCTAssertEqual(engine.sdkVersion, VersionManager.sdkVersion)
    }
    
    @MainActor
    func testShouldCallOnError_whenEnqueueTokenIsEmpty() async {
        let expectation = XCTestExpectation(description: "QueueItEngine should trigger onError for empty enqueue token")
        let listener = MockListener(expectation: expectation)
        let engine = makeEngine(listener: listener)
        
        await engine.runWithEnqueueToken("")
        await fulfillment(of: [expectation], timeout: 15.0)
        
        // Assert that onError was called with the correct details
        XCTAssertTrue(listener.onErrorCalled, "onError should have been called")
        XCTAssertEqual(listener.lastError?.code, .invalidResponse) // Assuming this is the error type for invalid input
        XCTAssertEqual(listener.lastErrorMessage, "EnqueueToken cannot be empty")
        
        // Also assert that other success/disabled callbacks were NOT called
        XCTAssertFalse(listener.onQueuePassedCalled, "onQueuePassed should not be called")
        XCTAssertFalse(listener.onQueueDisabledCalled, "onQueueDisabled should not be called")
    }
    
    @MainActor
    func testShouldCallOnError_whenEnqueueKeyIsEmpty() async {
        let expectation = XCTestExpectation(description: "QueueItEngine should trigger onError for empty enqueue key")
        let listener = MockListener(expectation: expectation)
        let engine = makeEngine(listener: listener)
        
        await engine.runWithEnqueueKey("")
        await fulfillment(of: [expectation], timeout: 15.0)
        
        XCTAssertTrue(listener.onErrorCalled, "onError should have been called")
        XCTAssertEqual(listener.lastError?.code, .invalidResponse) // Assuming this is the error type for invalid input
        XCTAssertEqual(listener.lastErrorMessage, "EnqueueKey cannot be empty")
        
        XCTAssertFalse(listener.onQueuePassedCalled, "onQueuePassed should not be called")
        XCTAssertFalse(listener.onQueueDisabledCalled, "onQueueDisabled should not be called")
    }
}
