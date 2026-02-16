import Foundation

public struct QueueError: LocalizedError, Sendable {
    public enum Code: String, Sendable {
        case noConnection = "NO_CONNECTION"
        case invalidResponse = "INVALID_RESPONSE"
        case queueitUnavailable = "QUEUEIT_UNAVAILABLE"
        case requestInProgress = "REQUEST_IN_PROGRESS"
        case apiError = "API_ERROR"
        case deviceIDError = "DEVICE_ID_ERROR"
    }

    public let code: Code
    public let message: String?

    public init(_ code: Code, message: String? = nil) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        if let message {
            return message
        }
        switch code {
        case .noConnection:
            return "No active internet connection."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .queueitUnavailable:
            return "The Queue-it service is currently unavailable."
        case .requestInProgress:
            return "A queue request is already in progress."
        case .apiError:
            return "A generic API error occurred."
        case .deviceIDError:
            return "Failed to retrieve a unique device identifier."
        }
    }
}
