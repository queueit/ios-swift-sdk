import QueueItKit
import XCTest

class MockListener: QueueListener {
    var expectation: XCTestExpectation?

    var onQueuePassedCalled = false
    var lastQueuePassedInfo: QueuePassedInfo?

    var onQueueDisabledCalled = false
    var lastQueueDisabledInfo: QueueDisabledInfo?

    var onErrorCalled = false
    var lastError: QueueError?
    var lastErrorMessage: String?

    var onQueueViewWillOpenCalled = false
    var onQueueItUnavailableCalled = false

    init(expectation: XCTestExpectation? = nil) {
        self.expectation = expectation
    }

    func onQueuePassed(_ info: QueuePassedInfo) {
        onQueuePassedCalled = true
        lastQueuePassedInfo = info
        expectation?.fulfill()
    }

    func onQueueDisabled(_ info: QueueDisabledInfo) {
        onQueueDisabledCalled = true
        lastQueueDisabledInfo = info
        expectation?.fulfill()
    }

    func onError(_ error: QueueError, errorMessage: String) {
        onErrorCalled = true
        lastError = error
        lastErrorMessage = errorMessage
        expectation?.fulfill()
    }

    func onQueueViewWillOpen() {
        onQueueViewWillOpenCalled = true
        expectation?.fulfill()
    }

    func onQueueItUnavailable() {
        onQueueItUnavailableCalled = true
        expectation?.fulfill()
    }
}
