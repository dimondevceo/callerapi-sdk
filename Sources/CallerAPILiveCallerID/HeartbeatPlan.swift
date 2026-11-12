import Foundation

/// Stored subscriber entitlement. The host SDK writes the same key.
/// A missing value means entitled, so an app that never calls setEntitled
/// keeps the previous behaviour.
enum MeteringEntitlement {
    static let key = "com.callerapi.sdk.entitled"

    static func isEntitled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    static func write(_ entitled: Bool, defaults: UserDefaults = .standard, appGroup: UserDefaults? = nil) {
        defaults.set(entitled, forKey: key)
        appGroup?.set(entitled, forKey: key)
    }
}

/// Whether the next heartbeat posts, and the feature_enabled value it carries.
///
/// A lapse sends one report with the feature off. Later calls skip the post.
/// The server keeps one row per device per month and bills the last value.
enum HeartbeatPlan: Equatable {
    case skip
    case send(featureEnabled: Bool)

    static func next(
        configured: Bool,
        meteringEnabled: Bool,
        entitled: Bool,
        extensionsOn: Bool,
        forceOff: Bool
    ) -> HeartbeatPlan {
        if !configured { return .skip }
        if !forceOff && !meteringEnabled { return .skip }
        if forceOff || !entitled { return .send(featureEnabled: false) }
        return .send(featureEnabled: extensionsOn)
    }

    static func allowsCallDirectorySync(entitled: Bool) -> Bool { entitled }

    static func allowsPeriodicHeartbeat(entitled: Bool, meteringEnabled: Bool) -> Bool {
        entitled && meteringEnabled
    }
}

/// Device id shared by Call Directory heartbeats and Live Caller ID heartbeats.
/// A stored fallback UUID wins over a later identifierForVendor.
/// One phone stays one device id.
enum DeviceIdentity {
    static let fallbackKey = "com.callerapi.lcid.deviceid"

    static func resolve(vendorID: String?, defaults: UserDefaults) -> String {
        // Once a fallback UUID is issued, keep it. A later vendor id would bill this phone twice.
        if let cached = defaults.string(forKey: fallbackKey), !cached.isEmpty {
            return cached
        }
        if let vendorID = vendorID, !vendorID.isEmpty { return vendorID }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: fallbackKey)
        return generated
    }
}
