import Foundation
import UIKit

public class UserAgentManager {
    private static let TAG = "UserAgentManager"

    @MainActor
    public static func getUserAgent(defaultUA: String?) -> String {
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ??
                      Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "UnknownApp"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let device = UIDevice.current
        let systemName = device.systemName
        let systemVersion = device.systemVersion
        let model = device.model

        let sdkInfo = "(sdk: \(VersionManager.sdkVersion))"

        var ua: String
        if let defaultUA = defaultUA, !defaultUA.isEmpty {
            ua = "\(defaultUA) \(sdkInfo)"
        } else {
           
            let deviceIdentifier = "\(model); CPU \(systemName) \(systemVersion.replacingOccurrences(of: ".", with: "_"))"
            ua = "\(appName)/\(appVersion) (\(deviceIdentifier)) \(sdkInfo)"
        }

        QueueItLogger.debug(UserAgentManager.TAG, "Constructed User Agent: \(ua)")
        return ua
    }
}
