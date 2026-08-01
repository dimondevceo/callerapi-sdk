import Foundation

// IdentityLookup (and the Live Caller ID Lookup types) exist only on iOS. The
// call-time / extension-management surface is therefore compiled under
// `#if os(iOS)`. The Foundation-only configuration + token-sharing logic below
// stays available on all platforms so it can be unit-tested with `swift test`
// on a Mac (see Tests/). The shipping product is iOS 18+ only.
#if os(iOS)
import IdentityLookup
#endif

/// CallerAPI's Live Caller ID Lookup integration surface.
///
/// This namespace is imported by **two** targets:
///
/// 1. **The Live Caller ID Lookup app extension** - its `@main` entry point
///    returns ``makeExtensionContext()`` from its `context` property. That is
///    the only thing the extension does; the iOS system runs the entire PIR /
///    Privacy Pass / Oblivious HTTP protocol against the CallerAPI backend on
///    every incoming call.
///
/// 2. **The host app** - uses the management helpers (``isDisabled(forExtensionWithIdentifier:)``,
///    ``openSettings()``, ``refreshPIRParameters(forExtensionWithIdentifier:)``)
///    to prompt the user to enable the extension and to refresh server params,
///    and ``setUserTierToken(_:)`` to hand a per-user bearer token to the
///    extension process.
///
/// All APIs require iOS 18.0+.
@available(iOS 18.0, *)
public enum CallerAPILiveCallerID {

    // MARK: - Configuration

    /// The App Group identifier shared between the host app and the extension
    /// (e.g. `"group.com.yourco.app"`).
    ///
    /// Resolution order:
    ///
    /// 1. an explicit assignment to this property;
    /// 2. the `CallerAPIAppGroup` key in the **current bundle's** Info.plist.
    ///
    /// Step 2 matters because the extension is a separate process with its own
    /// bundle: assigning this property in the host app cannot affect it. Without
    /// a per-target value the extension silently falls back to
    /// ``CallerAPILiveCallerIDConfiguration/production`` and never sees the
    /// per-user ``CallerAPILiveCallerIDConfiguration/userTierToken`` the host
    /// wrote — so every subscriber gets the default tier. Reading it from the
    /// extension's own Info.plist makes the wiring automatic; the generated
    /// project setup writes the key into both targets.
    ///
    /// When it resolves to `nil`, production defaults are used, which is enough
    /// for a zero-config integration that does not need per-user tokens.
    public static var appGroupIdentifier: String? {
        get { explicitAppGroupIdentifier ?? infoPlistAppGroupIdentifier }
        set { explicitAppGroupIdentifier = newValue }
    }

    private static var explicitAppGroupIdentifier: String?

    /// `Bundle.main` is the extension's own bundle inside an app extension, which
    /// is exactly the per-target value we want.
    private static let infoPlistAppGroupIdentifier: String? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CallerAPIAppGroup") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // The project template ships a placeholder; treat it as unset.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("group.com.yourco") else { return nil }
        return trimmed
    }()

    /// The configuration the extension will actually use: shared-container
    /// overrides if an ``appGroupIdentifier`` is set and values were written,
    /// otherwise production defaults.
    public static var effectiveConfiguration: CallerAPILiveCallerIDConfiguration {
        SharedStore.load(appGroup: appGroupIdentifier)
    }

    /// Stores a server-issued tier token in the App Group. Returns true when the
    /// stored value changed, so the caller knows whether to refresh the extension.
    ///
    /// The tier token identifies the customer to the Privacy Pass issuer, which is
    /// what lets the issuer return a signing key of that customer's own and count
    /// issuance against it. The heartbeat delivers it.
    ///
    /// Returns false without an App Group, and on an empty token. The extension
    /// reads the token from the shared container, so with no container there is
    /// nowhere to put it and the device keeps the bundled default. That undercounts
    /// one customer's attribution rather than breaking call screening.
    @discardableResult
    static func adoptTierToken(_ token: String) -> Bool {
        guard let appGroup = appGroupIdentifier, !token.isEmpty else { return false }
        let data = Data(token.utf8)
        guard SharedStore.load(appGroup: appGroup).userTierToken != data else { return false }
        SharedStore.setUserTierToken(data, appGroup: appGroup)
        return true
    }

    // MARK: - Extension entry point

#if os(iOS)
    /// Builds the `LiveCallerIDLookupExtensionContext` the system reads from the
    /// extension's `@main` entry point. Call this from your extension's
    /// `context` property (see `ExtensionTemplate/`).
    public static func makeExtensionContext() -> LiveCallerIDLookupExtensionContext {
        let config = effectiveConfiguration
        return LiveCallerIDLookupExtensionContext(
            serviceURL: config.serviceURL,
            tokenIssuerURL: config.tokenIssuerURL,
            userTierToken: config.userTierToken
        )
    }
#endif

    // MARK: - Host-app: sharing a per-user token

    /// Stores a per-user tier token in the shared App Group so the extension
    /// presents it to the Privacy Pass issuer. Call this from the host app
    /// after the user authenticates. Requires ``appGroupIdentifier`` to be set.
    ///
    /// After changing the token, call ``refreshPIRParameters(forExtensionWithIdentifier:)``
    /// (or ``reset(forExtensionWithIdentifier:)``) so the system re-reads it.
    public static func setUserTierToken(_ token: Data) {
        guard let appGroup = appGroupIdentifier else { return }
        SharedStore.setUserTierToken(token, appGroup: appGroup)
    }

    /// Overrides the service / issuer URLs in the shared container. Only needed
    /// to point the extension at a staging environment. Requires
    /// ``appGroupIdentifier`` to be set.
    public static func setEndpoints(serviceURL: URL? = nil, tokenIssuerURL: URL? = nil) {
        guard let appGroup = appGroupIdentifier else { return }
        SharedStore.setEndpoints(serviceURL: serviceURL, tokenIssuerURL: tokenIssuerURL, appGroup: appGroup)
    }

    /// Clears all shared overrides, reverting the extension to production
    /// defaults. Requires ``appGroupIdentifier`` to be set.
    public static func resetSharedOverrides() {
        guard let appGroup = appGroupIdentifier else { return }
        SharedStore.reset(appGroup: appGroup)
    }

    // MARK: - Host-app: managing the extension

#if os(iOS)
    /// The underlying system manager, for any API not surfaced by the
    /// convenience helpers below (e.g. `reset(forExtensionWithIdentifier:)`,
    /// `refreshExtensionContext(forExtensionWithIdentifier:)`).
    public static var manager: LiveCallerIDLookupManager { .shared }

    /// `true` when the user has **not** enabled the extension in Settings.
    /// Prompt the user and call ``openSettings()`` when this returns `true`.
    ///
    /// - Parameter identifier: the extension's bundle identifier, e.g.
    ///   `"com.yourco.app.LiveLookup"`.
    public static func isDisabled(forExtensionWithIdentifier identifier: String) -> Bool {
        LiveCallerIDLookupManager.shared.status(forExtensionWithIdentifier: identifier) == .disabled
    }

    /// Opens Settings so the user can enable the Live Caller ID Lookup extension.
    public static func openSettings() async throws {
        try await LiveCallerIDLookupManager.shared.openSettings()
    }

    /// Asks the system to refetch PIR parameters (dataset size, config hash)
    /// from the CallerAPI backend. Call after you change the user-tier token or
    /// learn (e.g. via push) that server-side parameters changed.
    ///
    /// - Parameter identifier: the extension's bundle identifier.
    public static func refreshPIRParameters(forExtensionWithIdentifier identifier: String) async throws {
        try await LiveCallerIDLookupManager.shared.refreshPIRParameters(forExtensionWithIdentifier: identifier)
    }
#endif
}
