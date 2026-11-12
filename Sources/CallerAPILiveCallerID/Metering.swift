// SDK metering & version-check (host-app only).
//
// This is the device check-in described in
// docs/lcid-metering-and-versioning-design.md. It counts active devices per MVNO
// client (for billing) and returns the SDK version policy. It is **fully separate
// from the Live Caller ID Lookup path** and never touches call blocking - iOS runs
// the lookup independently, and a failed/throttled heartbeat changes nothing about
// the user's calls.
//
// iOS-only: it reads `identifierForVendor` and schedules a `BGAppRefreshTask`.
#if os(iOS)
import Foundation
import UIKit
import CallKit
import BackgroundTasks

/// Configuration is written on the main thread at launch but read from background
/// refresh tasks and arbitrary caller queues, so every access takes the lock.
@available(iOS 18.0, *)
private final class MeteringStore: @unchecked Sendable {
    static let shared = MeteringStore()

    private let lock = NSLock()
    private var _clientKey: String?
    private var _extensionIdentifier: String?
    private var _callDirectoryExtensionIdentifier: String?
    private var _endpoint = URL(string: "https://api.callerapi.com/api/lcid/heartbeat")!
    private var _enabled = true
    private var _registeredTaskIdentifiers = Set<String>()

    private static let intervalKey = "com.callerapi.lcid.heartbeatIntervalHours"
    private static let attestRequestedKey = "com.callerapi.lcid.attestRequested"
    private static let defaultIntervalHours = 24

    private init() {}

    var clientKey: String? {
        get { lock.withLock { _clientKey } }
        set { lock.withLock { _clientKey = newValue } }
    }

    var extensionIdentifier: String? {
        get { lock.withLock { _extensionIdentifier } }
        set { lock.withLock { _extensionIdentifier = newValue } }
    }

    var callDirectoryExtensionIdentifier: String? {
        get { lock.withLock { _callDirectoryExtensionIdentifier } }
        set { lock.withLock { _callDirectoryExtensionIdentifier = newValue } }
    }

    var endpoint: URL {
        get { lock.withLock { _endpoint } }
        set { lock.withLock { _endpoint = newValue } }
    }

    /// The attestation challenge endpoint, derived from `endpoint` so a staging or
    /// regional override moves both together instead of leaving one pointed at
    /// production.
    var challengeEndpoint: URL {
        let base = endpoint
        return base
            .deletingLastPathComponent()          // …/api/lcid/
            .appendingPathComponent("attest")
            .appendingPathComponent("challenge")
    }

    /// Whether the server has asked this client for attestation material.
    ///
    /// Persisted because the heartbeat usually runs from a background refresh in a
    /// freshly launched process: held only in memory, a client in `enforce` mode
    /// would burn a refused request before every single check-in.
    var attestRequested: Bool {
        get { UserDefaults.standard.bool(forKey: Self.attestRequestedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.attestRequestedKey) }
    }

    var enabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }

    /// Server-advertised cadence, persisted so a cold launch schedules the right
    /// interval before the first heartbeat of the session comes back.
    var intervalHours: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.intervalKey)
            return stored > 0 ? stored : Self.defaultIntervalHours
        }
        set {
            guard newValue > 0 else { return }
            UserDefaults.standard.set(min(newValue, 7 * 24), forKey: Self.intervalKey)
        }
    }

    /// BGTaskScheduler traps on a duplicate identifier, so registration has to be
    /// idempotent: hosts legitimately call register… from more than one place
    /// (app delegate plus a SwiftUI scene, or after a state restore).
    /// Returns false if this identifier was already registered.
    func claimTaskIdentifier(_ identifier: String) -> Bool {
        lock.withLock { _registeredTaskIdentifiers.insert(identifier).inserted }
    }
}

// Device facts read on the main actor (UIDevice is main-actor isolated).
@available(iOS 18.0, *)
private enum MeteringDevice {
    /// Stable device id: IDFV, with a fallback cached in UserDefaults for the rare
    /// window where IDFV is nil (before first unlock).
    /// The fallback key lives on `DeviceIdentity` so an iOS 17 report and an
    /// iOS 18 report name the same phone.
    @MainActor static var deviceID: String {
        DeviceIdentity.resolve(
            vendorID: UIDevice.current.identifierForVendor?.uuidString,
            defaults: .standard
        )
    }

    @MainActor static var osVersion: String { UIDevice.current.systemVersion }
}

@available(iOS 18.0, *)
public extension CallerAPILiveCallerID {

    /// The server's SDK version policy, returned by ``sendHeartbeat()``.
    struct HeartbeatResult: Sendable {
        public let latestVersion: String
        public let minSupportedVersion: String
        public let isDeprecated: Bool
        public let heartbeatIntervalHours: Int
    }

    enum MeteringError: Error {
        case notConfigured
        case badResponse
        /// Server asked us to back off; `retryAfter` is its suggested delay.
        case throttled(retryAfter: TimeInterval?)
        /// The client requires device attestation and this heartbeat carried none.
        /// Handled internally by retrying once with material.
        case attestationRequired
        /// The server refused this device outright — an identity mismatch, a failed
        /// attestation, or the account's device ceiling. Retrying will not help;
        /// something has to change in provisioning or in the app first.
        case refused(reason: String)
    }

    /// Configure metering once at host-app launch.
    ///
    /// - Parameters:
    ///   - clientKey: the per-MVNO client key provisioned by CallerAPI (sent in
    ///     the `X-LCID-Client-Key` header). **Not** your dashboard API key.
    ///   - extensionIdentifier: your Live Caller ID Lookup extension's bundle id,
    ///     used to report whether the extension is enabled. Optional but
    ///     recommended - billing counts feature-enabled devices.
    ///   - endpoint: override the heartbeat URL (staging only).
    static func configureMetering(clientKey: String,
                                  extensionIdentifier: String? = nil,
                                  endpoint: URL? = nil,
                                  callDirectoryExtensionIdentifier: String? = nil) {
        let trimmed = clientKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // A silent no-op here is the classic "dashboard stays at zero and
            // nobody can be billed" footgun. Fail loudly and stay disabled.
            print("""
            [CallerAPI][LCID] configureMetering called with an EMPTY client key — \
            device metering is DISABLED. No heartbeats will be sent, so no devices \
            are counted or billed. Provision a key in the CallerAPI dashboard \
            (SDK Analytics → New app) and pass it as `clientKey`.
            """)
            MeteringStore.shared.enabled = false
            return
        }
        let s = MeteringStore.shared
        s.clientKey = trimmed
        s.extensionIdentifier = extensionIdentifier
        let callDirectory = callDirectoryExtensionIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        s.callDirectoryExtensionIdentifier = (callDirectory?.isEmpty == false) ? callDirectory : nil
        if let endpoint { s.endpoint = endpoint }
        s.enabled = MeteringEntitlement.isEntitled()
    }

    /// Apply a stored lapse or return. A lapse sends one report with the feature
    /// off, then stops later reports. A return sends the real extension state.
    public static func applyEntitlement(_ entitled: Bool) async {
        let s = MeteringStore.shared
        if entitled {
            if s.clientKey != nil { s.enabled = true }
            if let ext = s.extensionIdentifier, !ext.isEmpty {
                startAutomaticPrewarm(extensionIdentifier: ext)
            }
            if s.enabled {
                _ = try? await sendHeartbeat()
            }
            return
        }
        if s.clientKey != nil {
            _ = try? await sendHeartbeat(forceFeatureEnabled: false)
        }
        disableMetering()
    }

    /// Opt the device out of metering entirely (no further heartbeats are sent).
    static func disableMetering() { MeteringStore.shared.enabled = false }

    /// Send a single heartbeat. Safe to call on launch and from background
    /// refresh. Network failures throw to the caller but never affect call
    /// blocking. Returns the server's version policy.
    @discardableResult
    static func sendHeartbeat(forceFeatureEnabled: Bool? = nil) async throws -> HeartbeatResult {
        let s = MeteringStore.shared
        let forceOff = forceFeatureEnabled == false
        let entitled = MeteringEntitlement.isEntitled()
        let extensionsOn: Bool
        if s.clientKey != nil && s.enabled && entitled && !forceOff {
            extensionsOn = await extensionsEnabled()
        } else {
            extensionsOn = false
        }
        let plan = HeartbeatPlan.next(
            configured: s.clientKey != nil,
            meteringEnabled: s.enabled,
            entitled: entitled,
            extensionsOn: extensionsOn,
            forceOff: forceOff
        )
        guard case .send(let featureEnabled) = plan, let clientKey = s.clientKey else {
            throw MeteringError.notConfigured
        }

        do {
            return try await postHeartbeat(
                clientKey: clientKey,
                attest: s.attestRequested,
                featureEnabled: featureEnabled
            )
        } catch MeteringError.attestationRequired {
            // A client that requires attestation refuses the first heartbeat from a
            // device that has sent none. Retrying once with material metered this
            // device now, instead of leaving it uncounted until the next scheduled
            // refresh — which, on iOS, may be many hours away.
            s.attestRequested = true
            return try await postHeartbeat(clientKey: clientKey, attest: true, featureEnabled: featureEnabled)
        }
    }

    /// Live Caller ID on, or Call Directory on. Either one makes the phone billable.
    /// Both still produce one report, because the device id is the same.
    private static func extensionsEnabled() async -> Bool {
        let s = MeteringStore.shared
        var on = false
        if let ext = s.extensionIdentifier, !ext.isEmpty {
            on = !isDisabled(forExtensionWithIdentifier: ext)
        }
        if !on, let callDirectory = s.callDirectoryExtensionIdentifier, !callDirectory.isEmpty {
            on = await callDirectoryEnabled(callDirectory)
        }
        return on
    }

    private static func callDirectoryEnabled(_ identifier: String) async -> Bool {
        await withCheckedContinuation { cont in
            CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
                withIdentifier: identifier
            ) { status, _ in
                cont.resume(returning: status == .enabled)
            }
        }
    }

    private static func postHeartbeat(
        clientKey: String,
        attest: Bool,
        featureEnabled: Bool
    ) async throws -> HeartbeatResult {
        let s = MeteringStore.shared

        let deviceID = await MeteringDevice.deviceID
        let osVersion = await MeteringDevice.osVersion
        var body: [String: Any] = [
            "device_id": deviceID,
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "platform": "ios",
            "feature_enabled": featureEnabled,
            "sdk_version": sdkVersion,
            "os_version": osVersion,
        ]

        // Only fetched when the server has said it wants it, so a client with
        // attestation off never pays for a challenge round trip or an enclave
        // signature on every check-in.
        var sentAttestation = false
        if attest, AppAttest.isSupported,
           let challenge = try? await fetchChallenge(clientKey: clientKey, deviceID: deviceID),
           let material = await AppAttest.material(challenge: challenge) {
            body["attest_challenge"] = material.challenge
            body["attest_key_id"] = material.keyID
            if let attestation = material.attestation {
                body["attestation"] = attestation
                sentAttestation = true
            }
            if let assertion = material.assertion {
                body["assertion"] = assertion
            }
        }

        var req = URLRequest(url: s.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientKey, forHTTPHeaderField: "X-LCID-Client-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        // A background refresh window is short; never let one request sit for the
        // URLSession default of 60s and get the app killed for not completing.
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw MeteringError.badResponse }

        if http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw MeteringError.throttled(retryAfter: retryAfter)
        }
        if http.statusCode == 401 || http.statusCode == 402 || http.statusCode == 403 {
            throw refusal(status: http.statusCode, data: data)
        }
        guard http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MeteringError.badResponse
        }

        // The server accepted the attestation, so subsequent heartbeats can send the
        // much cheaper assertion. Recorded only on a 200: marking it earlier would
        // leave the device sending assertions for a key the server never stored.
        if sentAttestation { AppAttest.markAttested() }

        // Follow the server both ways, so turning attestation on for a client takes
        // effect within one heartbeat and turning it off stops the extra work just
        // as quickly.
        s.attestRequested = json["attest_requested"] as? Bool ?? false

        // The tier token identifies this customer to the Privacy Pass issuer, which
        // is what lets the issuer hand back a signing key of its own and count
        // issuance against it. The heartbeat is the only authenticated channel to
        // the device, so this is the only way it can arrive.
        //
        // Store it, and only when it changed: writing on every heartbeat would
        // churn the App Group and force a needless extension refresh.
        if let tierToken = json["lcid_tier_token"] as? String,
           adoptTierToken(tierToken),
           let ext = s.extensionIdentifier {
            // The system caches the extension context, so a changed token only takes
            // effect after a refresh. Without this the first month of a new client's
            // issuance would land in the shared bucket.
            Task { try? await refreshPIRParameters(forExtensionWithIdentifier: ext) }
        }

        let result = HeartbeatResult(
            latestVersion: json["latest_sdk_version"] as? String ?? sdkVersion,
            minSupportedVersion: json["min_supported_sdk_version"] as? String ?? sdkVersion,
            isDeprecated: json["sdk_deprecated"] as? Bool ?? false,
            heartbeatIntervalHours: json["heartbeat_interval_hours"] as? Int ?? s.intervalHours
        )
        // Adopt the server's cadence for the next scheduled refresh.
        s.intervalHours = result.heartbeatIntervalHours
        if result.isDeprecated {
            print("""
            [CallerAPI][LCID] this SDK (\(sdkVersion)) is below the minimum supported \
            version (\(result.minSupportedVersion)) — update the CallerAPILiveCallerID \
            package to \(result.latestVersion).
            """)
        }
        return result
    }

    /// Fetches a single-use attestation challenge.
    ///
    /// The challenge has to be the server's: a device-chosen nonce would let
    /// captured material be replayed indefinitely, which is the whole thing
    /// attestation exists to prevent.
    private static func fetchChallenge(clientKey: String, deviceID: String) async throws -> String? {
        let s = MeteringStore.shared
        var req = URLRequest(url: s.challengeEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientKey, forHTTPHeaderField: "X-LCID-Client-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["device_id": deviceID])
        req.timeoutInterval = 10

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challenge = json["challenge"] as? String, !challenge.isEmpty else {
            return nil
        }
        return challenge
    }

    /// Turns a refusal into an error carrying the server's reason, and prints the
    /// remedy. These are provisioning problems a customer's engineer has to act on,
    /// so they must not be swallowed as ordinary network noise.
    private static func refusal(status: Int, data: Data) -> MeteringError {
        let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0?["error"] as? String } ?? "unknown"

        if reason == "assertion_no_key" {
            // The server has no key for us — an operator reset the client's
            // attestation state. Start over on the next heartbeat.
            AppAttest.forgetKey()
        }
        print("[CallerAPI][LCID] heartbeat refused (HTTP \(status)): \(reason). \(advice(for: reason))")
        if reason == "attestation_required" { return .attestationRequired }
        return .refused(reason: reason)
    }

    /// Groups the server's reason codes by remedy. The server keeps three dozen
    /// precise codes for its own audit trail; the action a customer must take is the
    /// same across each group.
    private static func advice(for reason: String) -> String {
        if reason == "bundle_missing" {
            return "This build did not report its bundle identifier. Update CallerAPILiveCallerID to \(sdkVersion) or later."
        }
        if reason == "bundle_mismatch" {
            return "The client key is provisioned for a different bundle identifier. Check Dashboard → SDK Analytics → app identity."
        }
        if reason == "attestation_required" || reason == "attestation_absent" || reason == "assertion_absent" {
            return "This client requires App Attest. It is unavailable on the simulator; test on a real device."
        }
        if reason == "attestation_development_build" {
            return "A development-profile build cannot attest against a client in enforce mode. Use a TestFlight or App Store build."
        }
        if reason == "assertion_replay" {
            return "The enclave signature counter did not advance, which usually means a restored or cloned installation."
        }
        if reason.hasPrefix("challenge_") || reason.hasSuffix("_nonce_mismatch") {
            return "The attestation challenge expired or was reused; it resolves on the next heartbeat."
        }
        if reason == "mau_cap_reached" {
            return "The account's monthly active device ceiling is reached, so new devices are not being admitted. Contact CallerAPI to raise the plan."
        }
        return "See docs/sdk-security-and-billing-model.md."
    }

    /// Register a `BGAppRefreshTask` that periodically sends a heartbeat so
    /// devices check in even when the user never reopens the app (LCID keeps
    /// working without a foreground launch).
    ///
    /// Call from `application(_:didFinishLaunchingWithOptions:)` **before** launch
    /// completes, and add `taskIdentifier` to the host app's Info.plist under
    /// `BGTaskSchedulerPermittedIdentifiers`.
    ///
    /// Calling this more than once with the same identifier is safe — the
    /// duplicate registration (which `BGTaskScheduler` treats as fatal) is
    /// skipped, and the next refresh is simply re-submitted.
    static func registerBackgroundHeartbeat(taskIdentifier: String) {
        guard MeteringStore.shared.claimTaskIdentifier(taskIdentifier) else {
            scheduleBackgroundHeartbeat(taskIdentifier: taskIdentifier)
            return
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            scheduleBackgroundHeartbeat(taskIdentifier: taskIdentifier)

            // setTaskCompleted must be called exactly once. Both the work and the
            // expiration handler race to finish the task, and calling it twice (or
            // never) gets the app's background refresh budget revoked.
            let completed = CompletionLatch()
            let work = Task {
                let ok: Bool
                if HeartbeatPlan.allowsPeriodicHeartbeat(
                    entitled: MeteringEntitlement.isEntitled(),
                    meteringEnabled: MeteringStore.shared.enabled
                ) {
                    ok = (try? await sendHeartbeat()) != nil
                } else {
                    ok = true
                }
                if completed.claim() { task.setTaskCompleted(success: ok) }
            }
            task.expirationHandler = {
                work.cancel()
                // Report failure so the scheduler knows the window was not enough.
                if completed.claim() { task.setTaskCompleted(success: false) }
            }
        }
        scheduleBackgroundHeartbeat(taskIdentifier: taskIdentifier)
    }

    /// Submit the next background-refresh request, using the cadence the server
    /// last advertised (`heartbeat_interval_hours`) rather than a fixed day.
    static func scheduleBackgroundHeartbeat(taskIdentifier: String) {
        let hours = MeteringStore.shared.intervalHours
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(hours) * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// One-shot guard: the first `claim()` returns true, every later one false.
private final class CompletionLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}
#endif
