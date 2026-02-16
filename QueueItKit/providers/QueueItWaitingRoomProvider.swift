import Foundation
import Combine
import UIKit

let INITIAL_WAIT_RETRY_SEC = 1
let MAX_RETRY_SEC = 10
let MAX_CONNECTION_RETRIES = 3

actor QueueItWaitingRoomProvider {
    private static let TAG = "QueueItWaitingRoomProvider"
    
    var isRequestInProgress = false
    let apiClient: QueueItApiClientProtocol
    
    private let customerId: String
    private let waitingRoomOrAliasId: String
    private let themeName: String?
    private let language: String?

    init(customerId: String, waitingRoomOrAliasId: String, themeName: String?, language: String? ,waitingRoomDomain: String? = nil, queuePathPrefix: String? = nil, apiClient: QueueItApiClientProtocol? = nil) {
        self.customerId = customerId
        self.waitingRoomOrAliasId = waitingRoomOrAliasId
        self.themeName = themeName
        self.language = language
        if let apiClient {
            self.apiClient = apiClient
        } else {
            self.apiClient = QueueItApiClient(customerId: customerId, waitingRoomOrAliasId: waitingRoomOrAliasId, waitingRoomDomain: waitingRoomDomain, queuePathPrefix: queuePathPrefix)
        }
        NetworkUtils.startMonitoring()
    }

    deinit {
        NetworkUtils.stopMonitoring()
    }

    nonisolated public var sdkVersion: String {
        return VersionManager.sdkVersion
    }
    
    func setIsRequestInProgress(_ isRequestInProgress: Bool) {
        self.isRequestInProgress = isRequestInProgress
    }

    public func getIsRequestInProgress() -> Bool {
        return isRequestInProgress
    }

    func tryEnqueue(enqueueToken: String?, enqueueKey: String?) async -> TryEnqueueResult {
        if isRequestInProgress {
            return TryEnqueueResult(error: QueueError(.requestInProgress), errorMessage: "Request is already in progress")
        }

        isRequestInProgress = true
        
        defer { isRequestInProgress = false }

        var result: TryEnqueueResult
        do {
            if !(await self.ensureNetworkConnection()) {
                return TryEnqueueResult(error: QueueError(.noConnection), errorMessage: "No internet connection")
            }

            let userId = await UserIdManager.getUserId()
            guard let validUserId = userId else {
                return TryEnqueueResult(error: QueueError(.deviceIDError), errorMessage: "Could not retrieve device ID")
            }

            let apiResult = try await self.tryEnqueueWithRetries(userId: validUserId, enqueueToken: enqueueToken, enqueueKey: enqueueKey)
            result = self.handleAppEnqueueResponse(apiResult: apiResult, userId: validUserId)

        } catch let error as QueueError {
            QueueItLogger.error(QueueItWaitingRoomProvider.TAG, "tryEnqueue failed with QueueError: \(error.localizedDescription)")
            result = TryEnqueueResult(error: error, errorMessage: error.localizedDescription)
        } catch {
            QueueItLogger.error(QueueItWaitingRoomProvider.TAG, "tryEnqueue failed: \(error.localizedDescription)")
            result = TryEnqueueResult(error: QueueError(.apiError), errorMessage: error.localizedDescription)
        }
        
        return result
    }

    private func ensureNetworkConnection() async -> Bool {
        var attempts = 0
        while attempts < MAX_CONNECTION_RETRIES {
            if await NetworkUtils.isOnline() {
                return true
            }
            attempts += 1
            if attempts < MAX_CONNECTION_RETRIES {
                QueueItLogger.debug(QueueItWaitingRoomProvider.TAG, "No connection, retrying in 1s (\(attempts)/\(MAX_CONNECTION_RETRIES))")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        QueueItLogger.error(QueueItWaitingRoomProvider.TAG, "Max connection retries reached.")
        return false
    }

    private func tryEnqueueWithRetries(userId: String, enqueueToken: String?, enqueueKey: String?) async throws -> EnqueueSuccessResponse {
        var currentRetryDelaySec = INITIAL_WAIT_RETRY_SEC
        var lastError: Error?

        while currentRetryDelaySec <= MAX_RETRY_SEC {
            do {
                let userAgent = await UserAgentManager.getUserAgent(defaultUA: nil)
                let result = try await self.apiClient.enqueue(
                    userId: userId,
                    userAgent: userAgent,
                    themeName: self.themeName,
                    language: self.language,
                    enqueueToken: enqueueToken,
                    enqueueKey: enqueueKey
                )
                return result
            } catch let error as QueueError {
                lastError = error
               
                if case .invalidResponse = error.code {
                    QueueItLogger.error(QueueItWaitingRoomProvider.TAG, "Client error: \(error.localizedDescription), not retrying.")
                    throw error
                }
                QueueItLogger.warn(QueueItWaitingRoomProvider.TAG, "Enqueue attempt failed: \(error.localizedDescription). Retrying in \(currentRetryDelaySec)s")
            } catch {
                lastError = error
                QueueItLogger.warn(QueueItWaitingRoomProvider.TAG, "Enqueue attempt failed with unknown error: \(error.localizedDescription). Retrying in \(currentRetryDelaySec)s \(error)")
            }

            try? await Task.sleep(nanoseconds: UInt64(currentRetryDelaySec) * 1_000_000_000)
            currentRetryDelaySec *= 2
        }

        QueueItLogger.error(QueueItWaitingRoomProvider.TAG, "Enqueue failed after multiple retries. Last error: \(lastError?.localizedDescription ?? "None")")
        throw lastError ?? QueueError(.queueitUnavailable)
    }

    func handleAppEnqueueResponse(apiResult: EnqueueSuccessResponse, userId: String) -> TryEnqueueResult {
        QueueItLogger.debug(QueueItWaitingRoomProvider.TAG, "apiResult: \(apiResult)")

        let queueItToken = apiResult.queueitToken
        let queueUrl = apiResult.queueUrl
        let targetUrl = apiResult.eventTargetUrl
        let queueUrlTtlInMinutes = apiResult.queueUrlTTLInMinutes

        let isPassedThrough = queueItToken != nil && !(queueItToken?.isEmpty ?? true)
        let redirectType = self.getRedirectTypeFromToken(queueItToken)

        let updatedQueueUrl = (queueUrl != nil && QueueUrlHelper.isUrlUpdateNeeded(queueUrlStr: queueUrl, userId: userId))
        ? QueueUrlHelper.updateUrl(queueUrlStr: queueUrl, userId: userId)
            : queueUrl

        let result = QueueTryPassResult(
            queueItToken: queueItToken,
            queueUrl: updatedQueueUrl,
            targetUrl: targetUrl,
            isPassedThrough: isPassedThrough,
            redirectType: redirectType,
            urlTTLInMinutes: queueUrlTtlInMinutes
        )
        
        QueueItLogger.debug(QueueItWaitingRoomProvider.TAG, "result: \(result)")
        return TryEnqueueResult(result: result)
    }

    func getRedirectTypeFromToken(_ queueItToken: String?) -> RedirectType {
        guard let queueItToken = queueItToken else {
            return .queue
        }
        if let match = queueItToken.range(of: "~rt_([a-zA-Z]+)~", options: .regularExpression) {
            let typeString = String(queueItToken[match]).replacingOccurrences(of: "~rt_", with: "").replacingOccurrences(of: "~", with: "")
            return RedirectType(rawValue: typeString) ?? .unknown
        } else {
           
            QueueItLogger.debug(QueueItWaitingRoomProvider.TAG, "No ~rt_ marker in token, assuming Unknown: \(queueItToken)")
            return .unknown
        }
    }
}
