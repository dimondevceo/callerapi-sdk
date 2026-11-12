import Foundation

/// Subscriber entitlement stored on the device.
///
/// The key matches `MeteringEntitlement.key` in the Live Caller ID sources.
/// A missing value means entitled.
enum StoredEntitlement {
    static let key = "com.callerapi.sdk.entitled"

    static func isEntitled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    static func write(_ entitled: Bool, defaults: UserDefaults = .standard, appGroupID: String? = nil) {
        defaults.set(entitled, forKey: key)
        if let appGroupID = appGroupID, let suite = UserDefaults(suiteName: appGroupID) {
            suite.set(entitled, forKey: key)
        }
    }

    static func allowsSync() -> Bool { isEntitled() }
}

/// Deletes a Call Directory blob. A missing file is a no-op.
enum HostBlocklistFile {
    static func remove(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: url)
    }
}
