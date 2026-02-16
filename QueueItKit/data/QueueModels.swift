import Foundation

public struct QueuePassedInfo {
    public let queueItToken: String?

    public init(queueItToken: String?) {
        self.queueItToken = queueItToken
    }
}

public struct QueueDisabledInfo {
    public let queueItToken: String?

    public init(queueItToken: String?) {
        self.queueItToken = queueItToken
    }
}

public enum RedirectType: String, Codable, CaseIterable, Sendable {
    case unknown = "unknown"
    case queue = "queue"
    case safetyNet = "safetynet"
    case afterEvent = "afterevent"
    case disabled = "disabled"
    case directLink = "directLink"
    case idle = "idle"
}

public struct QueueTryPassResult: Codable, Sendable {
    public let queueItToken: String?
    public let queueUrl: String?
    public let targetUrl: String?
    public let isPassedThrough: Bool
    public let redirectType: RedirectType
    public let urlTTLInMinutes: Int?

    public init(queueItToken: String?, queueUrl: String?, targetUrl: String?, isPassedThrough: Bool, redirectType: RedirectType, urlTTLInMinutes: Int?) {
        self.queueItToken = queueItToken
        self.queueUrl = queueUrl
        self.targetUrl = targetUrl
        self.isPassedThrough = isPassedThrough
        self.redirectType = redirectType
        self.urlTTLInMinutes = urlTTLInMinutes
    }

    enum CodingKeys: String, CodingKey {
        case queueItToken = "QueueitToken"
        case queueUrl = "QueueUrl"
        case targetUrl = "EventTargetUrl"
        case urlTTLInMinutes = "QueueUrlTTLInMinutes"
       
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queueItToken = try container.decodeIfPresent(String.self, forKey: .queueItToken)
        self.queueUrl = try container.decodeIfPresent(String.self, forKey: .queueUrl)
        self.targetUrl = try container.decodeIfPresent(String.self, forKey: .targetUrl)
        self.urlTTLInMinutes = try container.decodeIfPresent(Int.self, forKey: .urlTTLInMinutes)

        self.isPassedThrough = queueItToken != nil && !(queueItToken?.isEmpty ?? true)
        self.redirectType = Self.deriveRedirectType(from: self.queueItToken)
    }

    private static func deriveRedirectType(from token: String?) -> RedirectType {
        guard let token = token else { return .queue }
        if let range = token.range(of: "~rt_([a-zA-Z]+)~", options: .regularExpression) {
            let typeString = String(token[range]).replacingOccurrences(of: "~rt_", with: "").replacingOccurrences(of: "~", with: "")
            return RedirectType(rawValue: typeString) ?? .unknown
        }
        return .unknown
    }
}

public struct QueueItEngineOptions {
    public var webViewUserAgent: String?
    public var viewDelayMs: Int = 0

    public init(webViewUserAgent: String? = nil, viewDelayMs: Int = 0) {
        self.webViewUserAgent = webViewUserAgent
        self.viewDelayMs = viewDelayMs
    }
}
