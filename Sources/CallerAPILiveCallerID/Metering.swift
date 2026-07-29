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
import BackgroundTasks

/// Configuration is written on the main thread at launch but read from background
/// refresh tasks and arbitrary caller queues, so every access takes the lock.
@available(iOS 18.0, *)
private final class MeteringStore: @unchecked Sendable {
    static let shared = MeteringStore()

    private let lock = NSLock()
    private var _clientKey: String?
    private var _extensionIdentifier: String?
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
    private static let fallbackKey = "com.callerapi.lcid.deviceid"

    /// Stable device id: IDFV, with a fallback cached in UserDefaults for the rare
    /// window where IDFV is nil (before first unlock).
    @MainActor static var deviceID: String {
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        }
        let d = UserDefaults.standard
        if let cached = d.string(forKey: fallbackKey) {
            return cached
        }
        let generated = UUID().uuidString
        d.set(generated, forKey: fallbackKey)
        return generated
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
                                  endpoint: URL? = nil) {
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
        if let endpoint { s.endpoint = endpoint }
        s.enabled = true
    }

    /// Opt the device out of metering entirely (no further heartbeats are sent).
    static func disableMetering() { MeteringStore.shared.enabled = false }

    /// Send a single heartbeat. Safe to call on launch and from background
    /// refresh. Network failures throw to the caller but never affect call
    /// blocking. Returns the server's version policy.
    @discardableResult
    static func sendHeartbeat() async throws -> HeartbeatResult {
        let s = MeteringStore.shared
        guard s.enabled, let clientKey = s.clientKey else { throw MeteringError.notConfigured }

        do {
            return try await postHeartbeat(clientKey: clientKey, attest: s.attestRequested)
        } catch MeteringError.attestationRequired {
            // A client that requires attestation refuses the first heartbeat from a
            // device that has sent none. Retrying once with material metered this
            // device now, instead of leaving it uncounted until the next scheduled
            // refresh — which, on iOS, may be many hours away.
            s.attestRequested = true
            return try await postHeartbeat(clientKey: clientKey, attest: true)
        }
    }

    private static func postHeartbeat(clientKey: String, attest: Bool) async throws -> HeartbeatResult {
        let s = MeteringStore.shared

        var featureEnabled = false
        if let ext = s.extensionIdentifier {
            featureEnabled = !isDisabled(forExtensionWithIdentifier: ext)
        }

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
                let ok = (try? await sendHeartbeat()) != nil
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
