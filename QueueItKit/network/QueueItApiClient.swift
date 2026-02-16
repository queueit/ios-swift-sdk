import Foundation

struct API {
    static let scheme = "https"
    static let host = "%@.queue-it.net"
    static let hostWithCustomDomain = "%@"
    static let path = "/api/mobileapp/queue"
}

public protocol QueueItApiClientProtocol: Sendable {
    func enqueue(
        userId: String,
        userAgent: String,
        themeName: String?,
        language: String?,
        enqueueToken: String?,
        enqueueKey: String?
    ) async throws -> EnqueueSuccessResponse
}

public final class QueueItApiClient: QueueItApiClientProtocol {
    private static let TAG = "QueueItApiClient"
    
    private let customerId: String
    private let waitingRoomOrAliasId: String
    private let waitingRoomDomain: String?
    private let queuePathPrefix: String?

    public init(customerId: String, waitingRoomOrAliasId: String, waitingRoomDomain: String? = nil, queuePathPrefix: String? = nil) {
        self.customerId = customerId
        self.waitingRoomOrAliasId = waitingRoomOrAliasId
        self.waitingRoomDomain = waitingRoomDomain
        self.queuePathPrefix = queuePathPrefix
        
    }

    private func getEnqueueApiUrl(userId: String) -> URL? {
        let (hostname, path) = buildQueueURLString(waitingRoomDomain: waitingRoomDomain, queuePathPrefix: queuePathPrefix, customerId: customerId)
        var components = URLComponents()
        components.scheme = API.scheme
        components.host = hostname
        components.path = "\(path)\(API.path)/\(customerId)/\(waitingRoomOrAliasId)/enqueue"
        components.queryItems = [
            URLQueryItem(name: "userId", value: userId)
        ]
        return components.url
    }
    
    private func sanitizeQueuePathPrefix(_ queuePathPrefix: String) -> String {
        let slashSet = CharacterSet(charactersIn: "/ ")
        return queuePathPrefix.trimmingCharacters(in: slashSet)
    }
    
    private func buildQueueURLString(
        waitingRoomDomain: String?,
        queuePathPrefix: String?,
        customerId: String
    ) -> (String, String) {
        guard let waitingRoomDomain, !waitingRoomDomain.isEmpty else {
            return (String(format: API.host, customerId), "")
        }

        let newAPIDomain = waitingRoomDomain
        var newAPIPath = ""
        if let queuePathPrefix, !queuePathPrefix.isEmpty {
            let sanitized = sanitizeQueuePathPrefix(queuePathPrefix)
            newAPIPath = "/\(sanitized)"
        }
        return (String(format: API.hostWithCustomDomain, newAPIDomain), newAPIPath)
    }

    public func enqueue(
        userId: String,
        userAgent: String,
        themeName: String?,
        language: String?,
        enqueueToken: String?,
        enqueueKey: String?
    ) async throws -> EnqueueSuccessResponse {
        guard let url = getEnqueueApiUrl(userId: userId) else {
            QueueItLogger.error(QueueItApiClient.TAG, "Failed to construct API URL.")
            throw QueueError(.apiError)
        }

        let requestBody = EnqueueRequestBody(
            userId: userId,
            userAgent: userAgent,
            sdkVersion: VersionManager.sdkVersion,
            themeName: themeName,
            language: language,
            enqueueToken: enqueueToken,
            enqueueKey: enqueueKey
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        QueueItLogger.debug(QueueItApiClient.TAG, "API Call: POST \(url.absoluteString) Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "N/A")")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            QueueItLogger.error(QueueItApiClient.TAG, "Invalid HTTP response type.")
            throw QueueError(.invalidResponse)
        }

        QueueItLogger.debug(QueueItApiClient.TAG, "API Response: \(httpResponse.statusCode) Body: \(String(data: data, encoding: .utf8) ?? "N/A")")

        switch httpResponse.statusCode {
        case 200..<400:
            break
        case 400..<500:
            QueueItLogger.error(QueueItApiClient.TAG, "Client Error \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "Unknown response")")
            throw QueueError(.invalidResponse, message: "\(String(data: data, encoding: .utf8) ?? "N/A") (\(httpResponse.statusCode))")
        default:
            let errorMessage = "HTTP Error \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "Unknown response")"
            QueueItLogger.error(QueueItApiClient.TAG, errorMessage)
            throw QueueError(.apiError)
        }

        let decoder = JSONDecoder()
        do {
            let successResponse = try decoder.decode(EnqueueSuccessResponse.self, from: data)
            return successResponse
        } catch {
            QueueItLogger.error(QueueItApiClient.TAG, "JSON Parse Error: \(error) Body: \(String(data: data, encoding: .utf8) ?? "N/A")")
            throw QueueError(.invalidResponse, message: "\(String(data: data, encoding: .utf8) ?? "N/A") (\(httpResponse.statusCode))")
        }
    }
}
