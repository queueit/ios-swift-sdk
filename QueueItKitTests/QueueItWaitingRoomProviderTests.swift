import XCTest
@testable import QueueItKit // Replace with your actual module name

final class QueueItWaitingRoomProviderTests: XCTestCase {
    
    var provider: QueueItWaitingRoomProvider!
    var mockApiClient: MockQueueItApiClient!
    
    override func setUp() {
        super.setUp()
        
        // Initialize with mocks
        mockApiClient = MockQueueItApiClient()
        // We'll replace the apiClient after initialization since it's internal
        provider = QueueItWaitingRoomProvider(customerId: "testCustomer", waitingRoomOrAliasId: "testEvent", themeName: "testLayout", language: "en-US", apiClient: mockApiClient)
    }
    
    override func tearDown() {
        provider = nil
        mockApiClient = nil
        super.tearDown()
    }
    
    func testTryEnqueue_success_passThrough_queue() async throws {
        // Given: a successful enqueue that results in pass-through (no queue redirect)
        let expectedSuccessResponse = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: nil,
            queueUrlTTLInMinutes: nil,
            eventTargetUrl: "https://example.com/target",
            queueitToken: nil
        )
        
        mockApiClient.enqueueHandler = { _, _, _, _, _, _ in
            return expectedSuccessResponse
        }
        
        // When
        let result = await provider.tryEnqueue(enqueueToken: nil, enqueueKey: nil)
        
        // Then
        XCTAssertEqual(result.result?.isPassedThrough, false)
        XCTAssertNil(result.error)
        XCTAssertNotNil(result.result)
        XCTAssertTrue((result.result?.queueItToken ?? "").isEmpty)
        XCTAssertNil(result.result?.queueUrl)
        XCTAssertEqual(result.result?.redirectType, .queue)
        XCTAssertEqual(mockApiClient.enqueueCallCount, 1)
        XCTAssertEqual(mockApiClient.receivedthemeName, "testLayout")
        XCTAssertEqual(mockApiClient.receivedLanguage, "en-US")
        let isInProgress = await provider.isRequestInProgress
        XCTAssertFalse(isInProgress) // Should be false after completion
    }
    
    func testTryEnqueue_success_passedThrough_directLink() async throws {
        // Given
        let expectedSuccessResponse = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: nil,
            queueUrlTTLInMinutes: 0,
            eventTargetUrl: "https://example.com/target",
            queueitToken: "~rt_directLink~"
        )
        
        mockApiClient.enqueueHandler = { _, _, _, _, _, _ in
            return expectedSuccessResponse
        }
        
        // When
        let result = await provider.tryEnqueue(enqueueToken: nil, enqueueKey: nil)
        
        // Then
        XCTAssertEqual(result.result?.isPassedThrough, true)
        XCTAssertNil(result.error)
        XCTAssertNotNil(result.result)
        XCTAssertEqual(result.result?.queueItToken, "~rt_directLink~")
        XCTAssertNil(result.result?.queueUrl)
        XCTAssertEqual(result.result?.redirectType, .directLink)
        XCTAssertEqual(mockApiClient.enqueueCallCount, 1)
        let isInProgress = await provider.isRequestInProgress
        XCTAssertFalse(isInProgress)
    }
    
    func testTryEnqueue_apiClientFails_retriesAndSucceeds() async throws {
        // Given
        // Simulate API failing twice, then succeeding on the third attempt
        let expectedSuccessResponse = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: "https://example.queue-it.net/queue?c=c&e=e&q=q",
            queueUrlTTLInMinutes: 5,
            eventTargetUrl: nil,
            queueitToken: "~rt_queue~"
        )
        var calls = 0
        mockApiClient.enqueueHandler = { _, _, _, _, _, _ in
            calls += 1
            if calls < 3 { // Fail first two calls
                throw QueueError(.queueitUnavailable)
            } else { // Succeed on the third
                return expectedSuccessResponse
            }
        }
        
        // When
        let result = await provider.tryEnqueue(enqueueToken: nil, enqueueKey: nil)
        
        // Then
        XCTAssertEqual(result.result?.isPassedThrough, true)
        XCTAssertNil(result.error)
        XCTAssertNotNil(result.result)
        XCTAssertEqual(mockApiClient.enqueueCallCount, 3) // Should retry twice and succeed
        XCTAssertEqual(result.result?.queueItToken, "~rt_queue~")
        let isInProgress = await provider.isRequestInProgress
        XCTAssertFalse(isInProgress)
    }
    
    func testTryEnqueue_apiClientFails_maxRetriesReached() async {
        // Given
        mockApiClient.enqueueHandler = { _, _, _, _, _, _ in
            throw QueueError(.queueitUnavailable)
        }
        
        // When
        let result = await provider.tryEnqueue(enqueueToken: nil, enqueueKey: nil)
        
        // Then
        XCTAssertNil(result.result?.isPassedThrough)
        XCTAssertEqual(result.error?.code, .queueitUnavailable) // Should reflect the last error
        XCTAssertNotNil(result.errorMessage)
        XCTAssertNil(result.result)
        // Initial delay 1, then 2, then 4. Max is 10. So 4 attempts.
        // It's 1 attempt + 3 retries = 4 calls.
        // The retry loop runs while `currentRetryDelaySec <= MAX_RETRY_SEC`.
        // 1st call (currentRetryDelaySec=1), sleeps 1
        // 2nd call (currentRetryDelaySec=2), sleeps 2
        // 3rd call (currentRetryDelaySec=4), sleeps 4
        // 4th call (currentRetryDelaySec=8), sleeps 8
        // 5th call (currentRetryDelaySec=16), now currentRetryDelaySec > MAX_RETRY_SEC (10), so loop exits.
        // So, it should call 4 times.
        XCTAssertEqual(mockApiClient.enqueueCallCount, 4)
        let isInProgress = await provider.isRequestInProgress
        XCTAssertFalse(isInProgress)
    }
    
    func testTryEnqueue_apiClientFails_clientError_noRetry() async {
        // Given
        mockApiClient.queueError = QueueError(.invalidResponse)
        
        // When
        let result = await provider.tryEnqueue(enqueueToken: nil, enqueueKey: nil)
        
        // Then
        XCTAssertNil(result.result?.isPassedThrough)
        XCTAssertEqual(result.error?.code, .invalidResponse)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertNil(result.result)
        XCTAssertEqual(mockApiClient.enqueueCallCount, 1) // Should not retry for client errors
        let isInProgress = await provider.isRequestInProgress
        XCTAssertFalse(isInProgress)
    }
    
    func testTryEnqueue_requestAlreadyInProgress() async {
        // Given
        await provider.setIsRequestInProgress(true) // Manually set request as in progress
        
        // When
        let result = await provider.tryEnqueue(enqueueToken: nil, enqueueKey: nil)
        
        // Then
        XCTAssertNil(result.result?.isPassedThrough)
        XCTAssertEqual(result.error?.code, .requestInProgress)
        XCTAssertEqual(result.errorMessage, "Request is already in progress")
        XCTAssertNil(result.result)
        XCTAssertEqual(mockApiClient.enqueueCallCount, 0)
        let isInProgress = await provider.isRequestInProgress
        XCTAssertTrue(isInProgress) // Should still be true as it was never reset by this call
    }
    
    func testTryEnqueue_requestInProgress_afterCompletion() async {
        // Given
        let expectedSuccessResponse = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: "https://example.queue-it.net/queue?c=c&e=e&q=q",
            queueUrlTTLInMinutes: 5,
            eventTargetUrl: nil,
            queueitToken: "~rt_queue~",
        )
        mockApiClient.enqueueHandler = { _, _, _, _, _, _ in
            return expectedSuccessResponse
        }
        
        _ = await provider.tryEnqueue(enqueueToken: nil, enqueueKey: nil)
        
        let isInProgressAfterFirst = await provider.isRequestInProgress
        XCTAssertFalse(isInProgressAfterFirst) // Should be false after first call
        
        // When
        let result = await provider.tryEnqueue(enqueueToken: nil, enqueueKey: nil)
        
        // Then
        XCTAssertEqual(result.result?.isPassedThrough, true)
        XCTAssertEqual(mockApiClient.enqueueCallCount, 2)
        
        let isInProgressAfterSecond = await provider.isRequestInProgress
        XCTAssertFalse(isInProgressAfterSecond)
    }
    
    func testTryEnqueue_withEnqueueTokenAndKey() async throws {
        // Given
        let expectedSuccessResponse = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: "https://example.queue-it.net/queue?c=c&e=e&q=q",
            queueUrlTTLInMinutes: 5,
            eventTargetUrl: nil,
            queueitToken: "~rt_queue~",
        )
        mockApiClient.enqueueHandler = { _, _, _, _, _, _ in
            return expectedSuccessResponse
        }
        
        let testEnqueueToken = "someTestToken"
        let testEnqueueKey = "someTestKey"
        
        // When
        _ = await provider.tryEnqueue(enqueueToken: testEnqueueToken, enqueueKey: testEnqueueKey)
        
        // Then
        XCTAssertEqual(mockApiClient.receivedEnqueueToken, testEnqueueToken)
        XCTAssertEqual(mockApiClient.receivedEnqueueKey, testEnqueueKey)
        XCTAssertEqual(mockApiClient.enqueueCallCount, 1)
    }
    
    func testGetRedirectTypeFromToken_queue() async {
        let token = "~rt_queue~"
        let result = await provider.getRedirectTypeFromToken(token) // Assuming getRedirectTypeFromToken is internal, you might need to make it public for direct testing or test via tryEnqueue
        XCTAssertEqual(result, RedirectType.queue)
    }
    
    func testGetRedirectTypeFromToken_directLink() async {
        let token = "~rt_directLink~"
        let result = await provider.getRedirectTypeFromToken(token)
        XCTAssertEqual(result, RedirectType.directLink)
    }
    
    func testGetRedirectTypeFromToken_safetyNet() async {
        let token = "~rt_safetynet~"
        let result = await provider.getRedirectTypeFromToken(token)
        XCTAssertEqual(result, RedirectType.safetyNet)
    }
    
    func testGetRedirectTypeFromToken_unknown() async {
        let token = "~rt_unknown~"
        let result = await provider.getRedirectTypeFromToken(token)
        XCTAssertEqual(result, RedirectType.unknown)
    }
    
    func testGetRedirectTypeFromToken_noMarker_assumesUnknown() async {
        let token = "someRandomTokenWithoutMarker"
        let result = await provider.getRedirectTypeFromToken(token)
        XCTAssertEqual(result, RedirectType.unknown)
    }
    
    func testGetRedirectTypeFromToken_nilToken_assumesQueue() async {
        let result = await provider.getRedirectTypeFromToken(nil)
        XCTAssertEqual(result, RedirectType.queue)
    }
    
    func testHandleAppEnqueueResponse_queue() async throws {
        // Given
        let response = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: "https://example.queue-it.net/queue?c=c&e=e&q=q",
            queueUrlTTLInMinutes: 5,
            eventTargetUrl: "https://example.com/target",
            queueitToken: "~rt_queue~"
        )
        let userId = "user1"
        
        // When
        let result = await provider.handleAppEnqueueResponse(apiResult: response, userId: userId)
        
        // Then
        XCTAssertEqual(result.result?.isPassedThrough, true)
        XCTAssertNotNil(result.result)
        XCTAssertEqual(result.result?.queueItToken, "~rt_queue~")
        XCTAssertTrue(result.result?.queueUrl?.contains("https://example.queue-it.net/queue") ?? false)
        XCTAssertTrue(result.result?.queueUrl?.contains(userId) ?? false)
        XCTAssertEqual(result.result?.redirectType, RedirectType.queue)
        XCTAssertEqual(result.result?.urlTTLInMinutes, 5)
        XCTAssertEqual(result.result?.targetUrl, "https://example.com/target")
    }
    
    func testHandleAppEnqueueResponse_directLink() async throws {
        // Given
        let response = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: nil,
            queueUrlTTLInMinutes: 0,
            eventTargetUrl: "https://example.com/target",
            queueitToken: "~rt_directLink~"
        )
        let userId = "user1" // UserId shouldn't be used as queueUrl is nil
        
        // When
        let result = await provider.handleAppEnqueueResponse(apiResult: response, userId: userId)
        
        // Then
        XCTAssertEqual(result.result?.isPassedThrough, true)
        XCTAssertNotNil(result.result)
        XCTAssertEqual(result.result?.queueItToken, "~rt_directLink~")
        XCTAssertNil(result.result?.queueUrl)
        XCTAssertEqual(result.result?.redirectType, RedirectType.directLink)
        XCTAssertEqual(result.result?.urlTTLInMinutes, 0)
        XCTAssertEqual(result.result?.targetUrl, "https://example.com/target")
    }
    
    func testHandleAppEnqueueResponse_safetyNet() async throws {
        // Given
        let response = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: nil,
            queueUrlTTLInMinutes: 0,
            eventTargetUrl: "https://example.com/target",
            queueitToken: "~rt_safetynet~"
        )
        let userId = "user1"
        
        // When
        let result = await provider.handleAppEnqueueResponse(apiResult: response, userId: userId)
        
        // Then
        XCTAssertEqual(result.result?.isPassedThrough, true)
        XCTAssertNotNil(result.result)
        XCTAssertEqual(result.result?.queueItToken, "~rt_safetynet~")
        XCTAssertNil(result.result?.queueUrl)
        XCTAssertEqual(result.result?.redirectType, RedirectType.safetyNet)
        XCTAssertEqual(result.result?.urlTTLInMinutes, 0)
        XCTAssertEqual(result.result?.targetUrl, "https://example.com/target")
    }
    
    func testHandleAppEnqueueResponse_noToken() async throws {
        // Given
        let response = EnqueueSuccessResponse(
            queueId: nil,
            queueUrl: nil,
            queueUrlTTLInMinutes: 0,
            eventTargetUrl: "https://example.com/target",
            queueitToken: nil // Key condition: nil token
        )
        let userId = "user1"
        
        // When
        let result = await provider.handleAppEnqueueResponse(apiResult: response, userId: userId)
        
        // Then
        XCTAssertEqual(result.result?.isPassedThrough, false)
        XCTAssertNotNil(result.result)
        XCTAssertNil(result.result?.queueItToken)
        XCTAssertNil(result.result?.queueUrl)
        XCTAssertEqual(result.result?.redirectType, RedirectType.queue) // This is the default if token is nil
        XCTAssertEqual(result.result?.urlTTLInMinutes, 0)
        XCTAssertEqual(result.result?.targetUrl, "https://example.com/target")
    }
}
