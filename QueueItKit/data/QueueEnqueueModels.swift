struct EnqueueRequestBody: Encodable {
    let userId: String
    let userAgent: String
    let sdkVersion: String
    let themeName: String?
    let language: String?
    let enqueueToken: String?
    let enqueueKey: String?

    private enum CodingKeys: String, CodingKey {
        case userId, userAgent, sdkVersion, themeName, language, enqueueToken, enqueueKey
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(userAgent, forKey: .userAgent)
        try container.encode(sdkVersion, forKey: .sdkVersion)
        try container.encodeIfPresent(themeName, forKey: .themeName)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(enqueueToken, forKey: .enqueueToken)
        try container.encodeIfPresent(enqueueKey, forKey: .enqueueKey)
    }
}

public struct EnqueueSuccessResponse: Decodable, Sendable {
    let queueId: String?
    let queueUrl: String?
    private let queueUrlTTLInMinutesString: String?
    let eventTargetUrl: String?
    let queueitToken: String?
    
    var queueUrlTTLInMinutes: Int? {
        get {
            return if let queueUrlTTLInMinutesString, let val = Int(queueUrlTTLInMinutesString) { val } else { nil }
        }
    }
    
    init(
        queueId: String?,
        queueUrl: String?,
        queueUrlTTLInMinutes: Int?,
        eventTargetUrl: String?,
        queueitToken: String?
    ) {
        self.queueId = queueId
        self.queueUrl = queueUrl
        self.queueUrlTTLInMinutesString = queueUrlTTLInMinutes != nil ? "\(queueUrlTTLInMinutes!)" : nil
        self.eventTargetUrl = eventTargetUrl
        self.queueitToken = queueitToken
    }

    private enum CodingKeys: String, CodingKey {
        case queueId = "QueueId"
        case queueUrl = "QueueUrl"
        case queueUrlTTLInMinutesString = "QueueUrlTTLInMinutes"
        case eventTargetUrl = "EventTargetUrl"
        case queueitToken = "QueueitToken"
    }
}
