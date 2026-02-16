import Foundation
import Combine
import XCTest
@testable import QueueItKit

// Mock QueueItApiClient
class MockQueueItApiClient: QueueItApiClientProtocol, @unchecked Sendable {
    
    var queueError = QueueError(.queueitUnavailable)
    var enqueueHandler: ((
        String, // userId
        String?, // userAgent
        String?, // themeName
        String?, // language
        String?, // enqueueToken
        String?  // enqueueKey
    ) async throws -> EnqueueSuccessResponse)?
    
    var enqueueCallCount = 0
    var receivedUserId: String?
    var receivedUserAgent: String?
    var receivedthemeName: String?
    var receivedLanguage: String?
    var receivedEnqueueToken: String?
    var receivedEnqueueKey: String?

    init() {}

    func enqueue(userId: String, userAgent: String, themeName: String?, language: String?, enqueueToken: String?, enqueueKey: String?) async throws -> QueueItKit.EnqueueSuccessResponse {
        enqueueCallCount += 1
        receivedUserId = userId
        receivedUserAgent = userAgent
        receivedthemeName = themeName
        receivedLanguage = language
        receivedEnqueueToken = enqueueToken
        receivedEnqueueKey = enqueueKey

        if let handler = enqueueHandler {
            return try await handler(userId, userAgent, themeName, language, enqueueToken, enqueueKey)
        } else {
            // Default behavior if no specific handler is set for a test
            throw queueError
        }
    }
}
