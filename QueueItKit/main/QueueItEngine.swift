import Foundation
import Combine
import UIKit
import WebKit

public class QueueItEngine {
    private static let TAG = "QueueItEngine"
    private let provider: QueueItWaitingRoomProvider
    public let viewManager: QueueItViewManager
    private var options: QueueItEngineOptions
    public weak var queueListener: QueueListener?
    private let customerId: String
    private let waitingRoomOrAliasId: String
    private let themeName: String?
    private let language: String?

    @MainActor
    public init(
        customerId: String,
        waitingRoomOrAliasId: String,
        queueListener: QueueListener,
        themeName: String? = nil,
        language: String? = nil,
        options: QueueItEngineOptions? = nil,
        webView: WKWebView? = nil,
        waitingRoomDomain: String? = nil,
        queuePathPrefix: String? = nil
    ) {
        self.customerId = customerId
        self.waitingRoomOrAliasId = waitingRoomOrAliasId
        self.queueListener = queueListener
        self.themeName = themeName
        self.language = language
        self.options = options ?? QueueItEngineOptions()
        self.provider = QueueItWaitingRoomProvider(customerId: customerId, waitingRoomOrAliasId: waitingRoomOrAliasId, themeName: themeName, language: language, waitingRoomDomain: waitingRoomDomain, queuePathPrefix: queuePathPrefix)
        self.viewManager = QueueItViewManager(queueListener: queueListener, options: self.options, webView: webView, waitingRoomDomain: waitingRoomDomain, queuePathPrefix: queuePathPrefix)

        QueueItLogger.info(QueueItEngine.TAG, "QueueItEngine initialized. SDK Version: \(self.sdkVersion)")
    }
    
    public var sdkVersion: String {
        return VersionManager.sdkVersion
    }

    public func run() async {
        QueueItLogger.debug(QueueItEngine.TAG, "run() called")
        await self.runWithConnection(enqueueToken: nil, enqueueKey: nil)
    }

    public func runWithEnqueueToken(_ enqueueToken: String) async {
        QueueItLogger.debug(QueueItEngine.TAG, "runWithEnqueueToken() called")
        guard !enqueueToken.isEmpty else {
             QueueItLogger.error(QueueItEngine.TAG, "EnqueueToken cannot be empty")
             self.queueListener?.onError(QueueError(.invalidResponse), errorMessage: "EnqueueToken cannot be empty")
             return
        }
        await self.runWithConnection(enqueueToken: enqueueToken, enqueueKey: nil)
    }

    public func runWithEnqueueKey(_ enqueueKey: String) async {
        QueueItLogger.debug(QueueItEngine.TAG, "runWithEnqueueKey() called")
         guard !enqueueKey.isEmpty else {
             QueueItLogger.error(QueueItEngine.TAG, "EnqueueKey cannot be empty")
             self.queueListener?.onError(QueueError(.invalidResponse), errorMessage: "EnqueueKey cannot be empty")
             return
         }
        await self.runWithConnection(enqueueToken: nil, enqueueKey: enqueueKey)
    }

    public func tryPass(enqueueToken: String? = nil, enqueueKey: String? = nil) async -> QueueTryPassResult? {
         QueueItLogger.debug(QueueItEngine.TAG, "tryPass(\(enqueueToken ?? "nil"), \(enqueueKey ?? "nil")) called")
         let tryEnqueueResult = await self.provider.tryEnqueue(enqueueToken: enqueueToken, enqueueKey: enqueueKey)
         if let error = tryEnqueueResult.error {
             self.handleCheckError(error, message: tryEnqueueResult.errorMessage)
             return nil
         }
         return tryEnqueueResult.result
    }

    @MainActor public func showQueue(queueTryPassResult: QueueTryPassResult) {
        QueueItLogger.debug(QueueItEngine.TAG, "showQueue() called")
        if queueTryPassResult.redirectType == .queue && queueTryPassResult.queueUrl != nil {
            self.viewManager.showQueue(queueTryPassResult)
        } else {
            QueueItLogger.warn(QueueItEngine.TAG, "showQueue() called but result type is \(queueTryPassResult.redirectType). View not shown.")
           
            if queueTryPassResult.isPassedThrough {
                self.queueListener?.onQueuePassed(QueuePassedInfo(queueItToken: queueTryPassResult.queueItToken))
            } else if queueTryPassResult.redirectType == .disabled ||
                       queueTryPassResult.redirectType == .afterEvent ||
                       queueTryPassResult.redirectType == .idle {
                self.queueListener?.onQueueDisabled(QueueDisabledInfo(queueItToken: queueTryPassResult.queueItToken))
            }
        }
    }

    @MainActor private func runWithConnection(enqueueToken: String?, enqueueKey: String?) async {
        let tryEnqueueResult = await self.provider.tryEnqueue(enqueueToken: enqueueToken, enqueueKey: enqueueKey)
        QueueItLogger.debug(QueueItEngine.TAG, "tryEnqueueResult: \(tryEnqueueResult)")
        
        if let error = tryEnqueueResult.error {
            self.handleCheckError(error, message: tryEnqueueResult.errorMessage)
            return
        }
        
        guard let resultData = tryEnqueueResult.result else {
            self.handleCheckError(QueueError(.invalidResponse), message: "Check result was unexpectedly null")
            return
        }
        
        QueueItLogger.debug(QueueItEngine.TAG, "resultData: \(resultData)")
        if !resultData.isPassedThrough {
            self.viewManager.showQueue(resultData)
            QueueItLogger.info(QueueItEngine.TAG, "Enqueue required. Showing queue view.")
        } else {
           
            self.handlePassOrDisabled(result: resultData)
        }
    }

    @MainActor func handlePassOrDisabled(result: QueueTryPassResult) {
        switch result.redirectType {
        case .safetyNet, .directLink:
            QueueItLogger.info(QueueItEngine.TAG, "Queue Passed (Type: \(result.redirectType.rawValue)). Token: \(result.queueItToken ?? "nil")")
            self.queueListener?.onQueuePassed(QueuePassedInfo(queueItToken: result.queueItToken))
            break
        case .disabled, .afterEvent, .idle:
            QueueItLogger.info(QueueItEngine.TAG, "Queue Disabled (Type: \(result.redirectType.rawValue)). Token: \(result.queueItToken ?? "nil")")
            self.queueListener?.onQueueDisabled(QueueDisabledInfo(queueItToken: result.queueItToken))
            break
        default:
            QueueItLogger.info(QueueItEngine.TAG, "Queue Default (Type: \(result.redirectType.rawValue)). Token: \(result.queueItToken ?? "nil")")
            self.viewManager.showQueue(result)
        }
    }

    func handleCheckError(_ error: QueueError, message: String?) {
        let errorMessage = message ?? "An unknown error occurred"
        QueueItLogger.error(QueueItEngine.TAG, "Check failed: \(error.code.rawValue) - \(errorMessage)")
        switch error.code {
        case .noConnection:
            self.queueListener?.onError(error, errorMessage: errorMessage)
            break
        case .queueitUnavailable:
            self.queueListener?.onQueueItUnavailable()
            break
        case .requestInProgress:
            QueueItLogger.warn(QueueItEngine.TAG, "Attempted action while request was in progress.")
           
            break
        case .invalidResponse, .apiError, .deviceIDError:
            self.queueListener?.onError(error, errorMessage: errorMessage)
            break
        }
    }
}
