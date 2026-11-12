#if os(iOS)
import Foundation
import UIKit
import IdentityLookup

/// Host-app automation for Live Caller ID Lookup.
///
/// Call ``CallerAPILiveCallerID/bootstrap(_:)`` once from
/// `application(_:didFinishLaunchingWithOptions:)` to wire metering, background
/// heartbeat, and automatic LCID prewarm (launch + every foreground) so the
/// first incoming call is not racing a cold PAT/PIR path.
@available(iOS 18.0, *)
public extension CallerAPILiveCallerID {

    struct BootstrapOptions: Sendable {
        /// Live Caller ID Lookup extension bundle id (nested under the host app).
        public let extensionIdentifier: String
        /// Per-MVNO client key from CallerAPI dashboard (SDK Analytics → New app).
        public let lcidClientKey: String
        /// `BGTaskSchedulerPermittedIdentifiers` entry for LCID metering. Optional
        /// but recommended for billing when the user rarely opens the app.
        public let heartbeatTaskIdentifier: String?
        /// App Group for per-user tier tokens (optional). When set, also assign
        /// ``CallerAPILiveCallerID/appGroupIdentifier`` before bootstrap.
        public let appGroupIdentifier: String?
        /// Call Directory extension id. On iOS 18 a phone with only this extension
        /// on is still reported. The device id stays the one Live Caller ID uses.
        public let callDirectoryExtensionIdentifier: String?

        public init(
            extensionIdentifier: String,
            lcidClientKey: String,
            heartbeatTaskIdentifier: String? = nil,
            appGroupIdentifier: String? = nil,
            callDirectoryExtensionIdentifier: String? = nil
        ) {
            self.extensionIdentifier = extensionIdentifier
            self.lcidClientKey = lcidClientKey
            self.heartbeatTaskIdentifier = heartbeatTaskIdentifier
            self.appGroupIdentifier = appGroupIdentifier
            self.callDirectoryExtensionIdentifier = callDirectoryExtensionIdentifier
        }
    }

    private static var bootstrapForegroundObserver: NSObjectProtocol?
    private static var bootstrappedExtensionID: String?

    /// One-shot host-app setup. Safe to call once at launch; idempotent.
    static func bootstrap(_ options: BootstrapOptions) {
        if let appGroup = options.appGroupIdentifier {
            appGroupIdentifier = appGroup
        }

        // The extension reads its own Info.plist, not the host's. Copy any host
        // override into the App Group so a customer on a dedicated host set only
        // has to set the two keys once, on the app target.
        if
            let appGroup = appGroupIdentifier,
            let overrides = CallerAPILiveCallerIDConfiguration.endpointOverrides()
        {
            SharedStore.setEndpoints(
                serviceURL: overrides.serviceURL,
                tokenIssuerURL: overrides.tokenIssuerURL,
                appGroup: appGroup
            )
        }

        configureMetering(
            clientKey: options.lcidClientKey,
            extensionIdentifier: options.extensionIdentifier,
            callDirectoryExtensionIdentifier: options.callDirectoryExtensionIdentifier
        )
        if let taskID = options.heartbeatTaskIdentifier {
            registerBackgroundHeartbeat(taskIdentifier: taskID)
        }

        if MeteringEntitlement.isEntitled() {
            startAutomaticPrewarm(extensionIdentifier: options.extensionIdentifier)
            Task {
                _ = try? await sendHeartbeat()
                _ = await prewarmIfEnabled(
                    extensionIdentifier: options.extensionIdentifier,
                    reason: "bootstrap"
                )
            }
        } else {
            Task {
                _ = try? await sendHeartbeat(forceFeatureEnabled: false)
                disableMetering()
            }
        }
    }

    /// Refetch PIR config / PAT / eval keys when the extension is enabled.
    /// Returns `false` when disabled in Settings or prewarm failed.
    ///
    /// Set `clearCachedLookups` after a package publish. A prior empty
    /// identity stays in the system cache until ``reset(forExtensionWithIdentifier:)``.
    @discardableResult
    static func prewarmIfEnabled(
        extensionIdentifier: String,
        reason: String = "manual",
        clearCachedLookups: Bool = false
    ) async -> Bool {
        // A cold `isDisabled` is not proof the user turned it off: CallDirectory
        // answers Cocoa 4099 for a few seconds after launch. Wait for the query
        // to settle before deciding, but never spawn the extension to find out.
        guard await waitUntilEnabled(forExtensionWithIdentifier: extensionIdentifier) else {
            NSLog("[CallerAPI][LCID] prewarm(%@) skipped — extension not enabled", reason)
            return false
        }
        let started = CFAbsoluteTimeGetCurrent()
        do {
            try await reprovision(
                forExtensionWithIdentifier: extensionIdentifier,
                clearCachedLookups: clearCachedLookups
            )
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            NSLog("[CallerAPI][LCID] prewarm(%@) ok in %dms", reason, ms)
            return true
        } catch {
            NSLog("[CallerAPI][LCID] prewarm(%@) failed: %@", reason, error.localizedDescription)
            return false
        }
    }

    /// Launch + foreground prewarm. Called by ``bootstrap(_:)``; rarely needed directly.
    static func startAutomaticPrewarm(extensionIdentifier: String) {
        guard bootstrappedExtensionID != extensionIdentifier else { return }
        bootstrappedExtensionID = extensionIdentifier

        bootstrapForegroundObserver.map { NotificationCenter.default.removeObserver($0) }
        bootstrapForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            guard MeteringEntitlement.isEntitled() else { return }
            Task {
                _ = await prewarmIfEnabled(
                    extensionIdentifier: extensionIdentifier,
                    reason: "foreground"
                )
            }
        }
    }
}
#endif
