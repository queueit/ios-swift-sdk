import UIKit

class UserIdManager {
    private static let TAG = "UserIdManager"
    
    @MainActor
    static func getUserId() -> String? {
       
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        } else {
            QueueItLogger.error(TAG, "Failed to get IDFV.")
            return nil
        }
    }
}
