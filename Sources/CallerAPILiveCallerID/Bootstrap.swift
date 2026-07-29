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

        public init(
            extensionIdentifier: String,
            lcidClientKey: String,
            heartbeatTaskIdentifier: String? = nil,
            appGroupIdentifier: String? = nil
        ) {
            self.extensionIdentifier = extensionIdentifier
            self.lcidClientKey = lcidClientKey
            self.heartbeatTaskIdentifier = heartbeatTaskIdentifier
            self.appGroupIdentifier = appGroupIdentifier
        }
    }

    private static var bootstrapForegroundObserver: NSObjectProtocol?
    private static var bootstrappedExtensionID: String?

    /// One-shot host-app setup. Safe to call once at launch; idempotent.
    static func bootstrap(_ options: BootstrapOptions) {
        if let appGroup = options.appGroupIdentifier {
            appGroupIdentifier = appGroup
        }

        configureMetering(
            clientKey: options.lcidClientKey,
            extensionIdentifier: options.extensionIdentifier
        )
        if let taskID = options.heartbeatTaskIdentifier {
            registerBackgroundHeartbeat(taskIdentifier: taskID)
        }

        startAutomaticPrewarm(extensionIdentifier: options.extensionIdentifier)

        Task {
            _ = try? await sendHeartbeat()
            _ = await prewarmIfEnabled(
                extensionIdentifier: options.extensionIdentifier,
                reason: "bootstrap"
            )
        }
    }

    /// Refetch PIR config / PAT / eval keys when the extension is enabled.
    /// Returns `false` when disabled in Settings or prewarm failed.
    @discardableResult
    static func prewarmIfEnabled(
        extensionIdentifier: String,
        reason: String = "manual"
    ) async -> Bool {
        guard !isDisabled(forExtensionWithIdentifier: extensionIdentifier) else {
            NSLog("[CallerAPI][LCID] prewarm(%@) skipped — extension disabled", reason)
            return false
        }
        let started = CFAbsoluteTimeGetCurrent()
        do {
            if #available(iOS 18.1, *) {
                try await manager.refreshExtensionContext(
                    forExtensionWithIdentifier: extensionIdentifier
                )
            }
            try await refreshPIRParameters(forExtensionWithIdentifier: extensionIdentifier)
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
