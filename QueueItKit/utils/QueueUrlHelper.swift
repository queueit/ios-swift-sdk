import Foundation

enum QueueUrlHelper {
    private static let TAG = "QueueUrlHelper"

    static func getParameter(queryString: String, key: String) -> String? {
        guard !queryString.isEmpty else { return nil }
        let keyLower = key.lowercased()
        let components = queryString.split(separator: "&")
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let paramKey = String(parts[0]).lowercased()
                if paramKey == keyLower {
                    if let value = String(parts[1]).removingPercentEncoding {
                        return value.replacingOccurrences(of: "+", with: " ")
                    }
                    return String(parts[1])
                }
            }
        }
        return nil
    }

    static func isUrlUpdateNeeded(queueUrlStr: String?, userId: String?) -> Bool {
        guard let queueUrlStr = queueUrlStr, let userId = userId, !queueUrlStr.isEmpty else { return false }

        guard let url = URL(string: queueUrlStr), let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
           
            return true
        }

        let currentUserId = queryItems.first { $0.name.lowercased() == "userid" }?.value
        return currentUserId == nil || currentUserId != userId
    }

    static func updateUrl(queueUrlStr: String?, userId: String) -> String {
        guard let queueUrlStr = queueUrlStr, !queueUrlStr.isEmpty else { return "" }

        var components = URLComponents(string: queueUrlStr)
        var existingQueryItems = components?.queryItems ?? []

        existingQueryItems.removeAll { $0.name.lowercased() == "userid" }

        existingQueryItems.append(URLQueryItem(name: "userId", value: userId))

        components?.queryItems = existingQueryItems
        return components?.string ?? queueUrlStr
    }
}
