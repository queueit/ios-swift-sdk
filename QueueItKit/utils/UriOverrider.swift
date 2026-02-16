import Foundation

enum UriOverrideResult {
    case loadInWebview
    case passed
    case close
    case restartSession
    case openExternal
    case block
    case `default`
}

struct UriOverrideResponse {
    public let action: UriOverrideResult
    public let modifiedUrl: String?
    public let queueItToken: String?

    public init(action: UriOverrideResult, modifiedUrl: String? = nil, queueItToken: String? = nil) {
        self.action = action
        self.modifiedUrl = modifiedUrl
        self.queueItToken = queueItToken
    }
}

class UriOverrider {
    private static let TAG = "UriOverrider"
    private var queueHost: String?
    private var targetHost: String?
    private var targetPath: String?
    private var userId: String?

    init() {}

    func setQueueUrl(_ queueUrlStr: String?) {
        self.queueHost = URL(string: queueUrlStr ?? "")?.host?.lowercased()
        QueueItLogger.debug(UriOverrider.TAG, "Queue host set to: \(self.queueHost ?? "nil")")
    }

    func setTargetUrl(_ targetUrlStr: String?) {
        if let url = URL(string: targetUrlStr ?? "") {
            self.targetHost = url.host?.lowercased()
            self.targetPath = url.path.isEmpty ? "/" : url.path
        } else {
            self.targetHost = nil
            self.targetPath = nil
        }
        QueueItLogger.debug(UriOverrider.TAG, "Target host set to: \(self.targetHost ?? "nil"), Path set to: \(self.targetPath ?? "nil")")
    }

    func setUserId(_ userId: String?) {
        self.userId = userId
    }

    func handleNavigationRequest(_ destinationUrlStr: String) -> UriOverrideResponse {
        QueueItLogger.debug(UriOverrider.TAG, "Intercepting: \(destinationUrlStr)")

        if destinationUrlStr.hasPrefix("queueit:") {
            var commandPart = String(destinationUrlStr.dropFirst("queueit:".count))
            if commandPart.hasPrefix("//") {
                commandPart = String(commandPart.dropFirst(2))
            }
            let action = commandPart.split(separator: "?")[0]

            if action == "close" {
                return UriOverrideResponse(action: .close)
            }
            if action == "restartSession" {
                return UriOverrideResponse(action: .restartSession)
            }

            QueueItLogger.warn(UriOverrider.TAG, "Unknown queueit action: \(action). Blocking.")
            return UriOverrideResponse(action: .block)
        }

        guard let destinationUrl = URL(string: destinationUrlStr) else {
            QueueItLogger.warn(UriOverrider.TAG, "Could not parse URL: \(destinationUrlStr). Treating as external.")
            return UriOverrideResponse(action: .openExternal)
        }

        let scheme = destinationUrl.scheme?.lowercased()
        let host = destinationUrl.host?.lowercased()
        let path = destinationUrl.path.isEmpty ? "/" : destinationUrl.path

        if scheme == "http" || scheme == "https" {
            if path.hasPrefix("/what-is-this.html") {
                return UriOverrideResponse(action: .block)
            }

            let isTargetDomain = (self.targetHost != nil && host == self.targetHost)
            let isTargetPath = (self.targetPath != nil && path == self.targetPath)
            
            if isTargetDomain && isTargetPath {
                let queueItToken = QueueUrlHelper.getParameter(queryString: destinationUrl.query ?? "", key: "queueittoken")
                if queueItToken != nil {
                    return UriOverrideResponse(action: .passed, queueItToken: queueItToken)
                }
            }

            let isQueueItDomain = (self.queueHost != nil && host == self.queueHost)
            if isQueueItDomain {
                if let userId = self.userId, QueueUrlHelper.isUrlUpdateNeeded(queueUrlStr: destinationUrlStr, userId: userId) {
                    let rewrittenUrl = QueueUrlHelper.updateUrl(queueUrlStr: destinationUrlStr, userId: userId)
                    return UriOverrideResponse(action: .loadInWebview, modifiedUrl: rewrittenUrl)
                }
                return UriOverrideResponse(action: .`default`)
            }

            return UriOverrideResponse(action: .openExternal)
        }

        return UriOverrideResponse(action: .openExternal)
    }
}
