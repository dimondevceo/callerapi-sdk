import Foundation

/// App Group-backed storage that lets the host app push runtime overrides
/// (most importantly a per-user `userTierToken`) into the separate Live Caller
/// ID Lookup extension process.
///
/// The extension runs in its own sandbox and cannot read the host app's
/// keychain or `UserDefaults`. The only supported shared channel is an
/// App Group container, which both the app target and the extension target
/// must declare (`com.apple.security.application-groups`).
///
/// All keys are namespaced under `com.callerapi.lcid.*`. If no App Group is
/// configured, or no override has been written, callers fall back to
/// ``CallerAPILiveCallerIDConfiguration/production``.
enum SharedStore {

    private static let serviceURLKey = "com.callerapi.lcid.serviceURL"
    private static let tokenIssuerURLKey = "com.callerapi.lcid.tokenIssuerURL"
    private static let userTierTokenKey = "com.callerapi.lcid.userTierToken"

    /// Reads the effective configuration for the given App Group, falling back
    /// to compiled-in production defaults for any value that is absent.
    static func load(appGroup: String?) -> CallerAPILiveCallerIDConfiguration {
        var config = CallerAPILiveCallerIDConfiguration.production
        guard
            let appGroup,
            let defaults = UserDefaults(suiteName: appGroup)
        else {
            return config
        }

        if let raw = defaults.string(forKey: serviceURLKey), let url = URL(string: raw) {
            config.serviceURL = url
        }
        if let raw = defaults.string(forKey: tokenIssuerURLKey), let url = URL(string: raw) {
            config.tokenIssuerURL = url
        }
        if let token = defaults.data(forKey: userTierTokenKey), !token.isEmpty {
            config.userTierToken = token
        }
        return config
    }

    /// Persists a per-user tier token into the shared container so the
    /// extension picks it up on its next context read.
    static func setUserTierToken(_ token: Data, appGroup: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.set(token, forKey: userTierTokenKey)
    }

    /// Overrides the service / issuer URLs in the shared container. Rarely
    /// needed - only for staging environments.
    static func setEndpoints(serviceURL: URL?, tokenIssuerURL: URL?, appGroup: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        if let serviceURL { defaults.set(serviceURL.absoluteString, forKey: serviceURLKey) }
        if let tokenIssuerURL { defaults.set(tokenIssuerURL.absoluteString, forKey: tokenIssuerURLKey) }
    }

    /// Clears all shared overrides (reverts the extension to production defaults).
    static func reset(appGroup: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        defaults.removeObject(forKey: serviceURLKey)
        defaults.removeObject(forKey: tokenIssuerURLKey)
        defaults.removeObject(forKey: userTierTokenKey)
    }
}
