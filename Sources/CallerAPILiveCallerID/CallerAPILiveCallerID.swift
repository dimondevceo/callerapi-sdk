import Foundation

// IdentityLookup (and the Live Caller ID Lookup types) exist only on iOS. The
// call-time / extension-management surface is therefore compiled under
// `#if os(iOS)`. The Foundation-only configuration + token-sharing logic below
// stays available on all platforms so it can be unit-tested with `swift test`
// on a Mac (see Tests/). The shipping product is iOS 18+ only.
#if os(iOS)
import IdentityLookup
// `LiveCallerIDLookupManager` reaches the system through the XPC service in
// `CallKit.framework/XPCServices/com.apple.CallKit.CallDirectory.xpc`. An
// XPCService name only resolves against the main bundle and the frameworks
// loaded in the process, so a host that links IdentityLookup alone fails every
// call with `bootstrap look-up: xpc_error=[3: No such process]`, surfaced as
// Cocoa 4099. Importing CallKit here autolinks it for every consumer.
import CallKit
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
    ///
    /// This is a plain query. It does not launch the extension.
    ///
    /// For a few seconds after app launch, and while CallDirectory is
    /// restarting, the system answers Cocoa 4099 and this reports `true` even
    /// though the user already enabled the extension. Poll it, show the state,
    /// and let the user act. Never launch the extension just to test the
    /// toggle: each probe spawns an `extensionkitservice` process, and a loop
    /// of them wedges the Settings toggle.
    ///
    /// - Parameter identifier: the extension's bundle identifier, e.g.
    ///   `"com.yourco.app.LiveLookup"`.
    public static func isDisabled(forExtensionWithIdentifier identifier: String) -> Bool {
        LiveCallerIDLookupManager.shared.status(forExtensionWithIdentifier: identifier) == .disabled
    }

    /// Polls ``isDisabled(forExtensionWithIdentifier:)`` until it reports
    /// enabled or `timeout` passes. Query only; the extension is never spawned.
    /// Returns `false` on timeout.
    @discardableResult
    public static func waitUntilEnabled(
        forExtensionWithIdentifier identifier: String,
        timeout: TimeInterval = 8
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !Task.isCancelled {
            if !isDisabled(forExtensionWithIdentifier: identifier) { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return !isDisabled(forExtensionWithIdentifier: identifier)
    }

    /// Cocoa 4099 / "Couldn't communicate with a helper application".
    public static func isCallDirectoryUnavailable(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == 4099 {
            return true
        }
        let text = ns.localizedDescription.lowercased()
        if text.contains("couldn't communicate with a helper") { return true }
        if text.contains("couldn’t communicate with a helper") { return true }
        if text.contains("calldirectory") && (text.contains("invalidated") || text.contains("check-in")) {
            return true
        }
        return false
    }

    /// First ExtensionKit call after an in-place app update. The host still
    /// points at the previous appex signature. Retry once; do not sit in a loop.
    public static func isStaleExtensionConnection(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "com.apple.extensionKit.errorDomain" && ns.code == 2
    }

    public static func isTransientExtensionError(_ error: Error) -> Bool {
        isCallDirectoryUnavailable(error) || isStaleExtensionConnection(error)
    }

    /// Opens Settings so the user can enable the Live Caller ID Lookup extension.
    public static func openSettings() async throws {
        try await LiveCallerIDLookupManager.shared.openSettings()
    }

    /// Asks the system to refetch PIR parameters (dataset size, config hash)
    /// from the CallerAPI backend. Call after you change the user-tier token or
    /// learn (e.g. via push) that server-side parameters changed.
    ///
    /// This does **not** drop a cached identity. A first lookup that returned
    /// empty stays empty until ``reset(forExtensionWithIdentifier:)``.
    ///
    /// - Parameter identifier: the extension's bundle identifier.
    public static func refreshPIRParameters(forExtensionWithIdentifier identifier: String) async throws {
        try await LiveCallerIDLookupManager.shared.refreshPIRParameters(forExtensionWithIdentifier: identifier)
    }

    /// Drops the system cache for this extension (tokens, eval keys, and
    /// cached identity / block results).
    ///
    /// Call this after a PIR package publish, or when the Phone UI keeps an
    /// empty name after the backend already answers. Then call
    /// ``reprovision(forExtensionWithIdentifier:clearCachedLookups:)`` or
    /// ``refreshPIRParameters(forExtensionWithIdentifier:)``.
    public static func reset(forExtensionWithIdentifier identifier: String) async throws {
        try await LiveCallerIDLookupManager.shared.reset(forExtensionWithIdentifier: identifier)
    }

    /// Forces the system to re-read ``makeExtensionContext()`` (URLs + tier
    /// token). Available on iOS 18.1+. No-op on 18.0.
    public static func refreshExtensionContext(forExtensionWithIdentifier identifier: String) async throws {
        if #available(iOS 18.1, *) {
            try await LiveCallerIDLookupManager.shared.refreshExtensionContext(forExtensionWithIdentifier: identifier)
        }
    }

    /// Apple's working sequence after a server-side PIR change: optional
    /// ``reset(forExtensionWithIdentifier:)``, then extension context, then
    /// PIR parameters. Without reset, iOS can keep a cached empty identity
    /// for the rest of `cache_expiry_minutes` (24 h in production).
    ///
    /// Each step spawns the extension, so this runs one pass with a single
    /// retry on a transient error. Do not wrap it in a polling loop.
    public static func reprovision(
        forExtensionWithIdentifier identifier: String,
        clearCachedLookups: Bool = false
    ) async throws {
        if clearCachedLookups {
            do {
                try await reset(forExtensionWithIdentifier: identifier)
            } catch {
                // Reset is the most fragile call: after an in-place install it
                // throws ExtensionKit 2 while the host still points at the old
                // appex. The refresh below is what the next call needs, so a
                // failed reset must not abort the sequence.
                NSLog("[CallerAPI][LCID] reset skipped: %@", error.localizedDescription)
            }
        }
        try await retryOnceIfTransient {
            try await refreshExtensionContext(forExtensionWithIdentifier: identifier)
            try await refreshPIRParameters(forExtensionWithIdentifier: identifier)
        }
    }

    private static func retryOnceIfTransient(
        _ operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
        } catch {
            NSLog("[CallerAPI][LCID] refresh failed: %@", error.localizedDescription)
            guard isTransientExtensionError(error) else { throw error }
            try? await Task.sleep(nanoseconds: 500_000_000)
            try await operation()
        }
    }
#endif
}
