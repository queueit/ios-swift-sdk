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

    var onUserExitedCount = 0
    var onUserExitedAction: (() -> Void)?
    var onQueueUrlChangedAction: (() -> Void)?
    var onWebViewClosedCalled = false
    private(set) var allCallsOnMainThread = true

    init(expectation: XCTestExpectation? = nil) {
        self.expectation = expectation
    }

    private func recordThread() {
        if !Thread.isMainThread {
            allCallsOnMainThread = false
        }
    }

    func onQueuePassed(_ info: QueuePassedInfo) {
        recordThread()
        onQueuePassedCalled = true
        lastQueuePassedInfo = info
        expectation?.fulfill()
    }

    func onQueueDisabled(_ info: QueueDisabledInfo) {
        recordThread()
        onQueueDisabledCalled = true
        lastQueueDisabledInfo = info
        expectation?.fulfill()
    }

    func onError(_ error: QueueError, errorMessage: String) {
        recordThread()
        onErrorCalled = true
        lastError = error
        lastErrorMessage = errorMessage
        expectation?.fulfill()
    }

    func onQueueViewWillOpen() {
        recordThread()
        onQueueViewWillOpenCalled = true
        expectation?.fulfill()
    }

    func onQueueItUnavailable() {
        recordThread()
        onQueueItUnavailableCalled = true
        expectation?.fulfill()
    }

    func onWebViewClosed() {
        recordThread()
        onWebViewClosedCalled = true
        expectation?.fulfill()
    }

    func onUserExited() {
        recordThread()
        onUserExitedCount += 1
        onUserExitedAction?()
    }

    func onQueueUrlChanged(_ url: String) {
        recordThread()
        onQueueUrlChangedAction?()
    }
}
