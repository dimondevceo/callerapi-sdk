import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif
// When consumed via SwiftPM the C core is a Clang module (the xcframework ships a
// module map). In the drag-and-drop path the symbols come from the bridging
// header instead, so this import is simply absent - hence the canImport guard.
#if canImport(CallerAPICCore)
import CallerAPICCore
#endif

/// CallerAPI SDK - privacy-preserving spam detection + caller labels.
///
/// Lookups use a k-anonymity hash-prefix protocol: the device reveals only a
/// bucket index (one of many candidates) to the server, fetches that whole
/// bucket, and matches the full-hash suffix locally. The server never learns the
/// queried number, and the device never holds the full dataset.
///
/// Note: this is a runtime lookup/enrichment SDK. Privacy-preserving call
/// *blocking* on iOS is provided separately by the Live Caller ID Lookup
/// (PIR) extension SDK - iOS has no on-device full list to block from here.
///
/// ```swift
/// CallerAPI.configure(CallerAPIConfig(
///     sdkKey: "<from the dashboard>",
///     sdkSecret: "<from the dashboard>"
/// ))
/// let spam  = try await CallerAPI.isSpam("+1234567890")
/// let label = try await CallerAPI.lookupLabel("+1234567890")
/// ```
public final class CallerAPI: @unchecked Sendable {

    /// Shared singleton.
    public static let shared = CallerAPI()

    private let queue = DispatchQueue(label: "com.callerapi.sdk", qos: .userInitiated)
    private var initialised = false
    private var initFailureLogged = false
    // os_log rather than Logger: Logger is iOS 14+, and this package supports older.
    private let log = OSLog(subsystem: "com.callerapi.sdk", category: "CallerAPI")

    private init() {}

    // MARK: - Lifecycle

    /// Initialises the native core if `configure` has not already done it.
    ///
    /// Falls back to the Info.plist credentials, which is the iOS counterpart of
    /// the Android manifest meta-data. Without that fallback the Flutter and React
    /// Native bridges could never authenticate: they call straight through to
    /// `isSpam` and `lookupLabel` and have nowhere to pass a credential.
    private func ensureInitialisedLocked() {
        guard !initialised else { return }
        initialiseLocked(with: CallerAPIConfig.fromInfoPlist())
    }

    private func initialiseLocked(with config: CallerAPIConfig) {
        guard !initialised else { return }

        // The core copies every string it is given, and treats an empty one as
        // absent, so an unset credential needs no special case here.
        let dir = cacheDirectory()
        let apiBase = config.apiBase ?? ""
        let sdkKey = config.sdkKey ?? ""
        let sdkSecret = config.sdkSecret ?? ""
        // The server checks a credential against the app it was issued to, so
        // report the bundle id. iOS has no analogue of the Android signing digest.
        let bundleID = Bundle.main.bundleIdentifier ?? ""

        let rc = dir.withCString { dirPtr in
            apiBase.withCString { apiBasePtr in
                sdkKey.withCString { sdkKeyPtr in
                    sdkSecret.withCString { sdkSecretPtr in
                        bundleID.withCString { bundleIDPtr in
                            var cfg = callerapi_config()
                            cfg.cache_dir = dirPtr
                            cfg.api_base = apiBasePtr
                            cfg.sdk_key = sdkKeyPtr
                            cfg.sdk_secret = sdkSecretPtr
                            cfg.package_name = bundleIDPtr
                            cfg.lookup_timeout_ms = config.lookupTimeoutMs
                            cfg.network_timeout_ms = config.networkTimeoutMs
                            return callerapi_init_ex(&cfg)
                        }
                    }
                }
            }
        }
        initialised = rc == 0

        // Say why. A missing credential pair otherwise produces an SDK that answers
        // every lookup with "not spam" and reports nothing: the one failure a
        // customer causes themselves is the one that looks like success.
        //
        // Once, not per lookup. A failed init leaves `initialised` false, so every
        // later lookup retries it, and an SDK that writes the same line into a
        // customer's console a hundred times has taught them to filter it out.
        if rc != 0 && !initFailureLogged {
            initFailureLogged = true
            if rc == -10 {
                os_log("""
                    CallerAPI has no credentials, so every lookup will report "not spam". \
                    Pass CallerAPIConfig(sdkKey:sdkSecret:) to configure, or set \
                    CallerAPISDKKey and CallerAPISDKSecret in the host Info.plist.
                    """, log: log, type: .error)
            } else {
                os_log("CallerAPI init failed with code %{public}d", log: log, type: .error, rc)
            }
        }
    }

    deinit {
        callerapi_cleanup()
    }

    // MARK: - Public API (static convenience)

    /// Supplies the credentials the SDK authenticates with, then starts metering.
    ///
    /// Call this once at launch, before the first lookup. Published artifacts
    /// carry no credentials, so a lookup made before this fails with
    /// `CallerAPIError` code -2.
    ///
    /// - Parameters:
    ///   - config: credentials and timeouts from the CallerAPI dashboard.
    ///   - featureEnabled: whether the user has spam protection turned on.
    ///     Reported for billing, since only enabled devices are billable.
    public static func configure(_ config: CallerAPIConfig, featureEnabled: Bool = true) {
        shared.queue.sync { shared.initialiseLocked(with: config) }
        setMetering(featureEnabled: featureEnabled && isEntitled())
    }

    /// Configure metering for MAU/billing: reports the stable per-vendor device
    /// id (IDFV) and whether the spam feature is enabled. Call once at launch.
    ///
    /// Takes the credentials from the host `Info.plist` (`CallerAPISDKKey` and
    /// `CallerAPISDKSecret`), or from the build if they are compiled in. Use
    /// ``configure(_:featureEnabled:)`` to pass them in code instead. One of the two
    /// is required: with neither, init fails and every lookup reports "not spam".
    public static func configure(featureEnabled: Bool = true) {
        shared.queue.sync { shared.ensureInitialisedLocked() }
        setMetering(featureEnabled: featureEnabled && isEntitled())
    }

    /// Whether the subscriber is entitled. Missing storage means yes.
    public static func isEntitled() -> Bool {
        StoredEntitlement.isEntitled()
    }

    /// Optional iOS 18 report. The Flutter and React Native plugins set this so a
    /// lapse sends the Live Caller ID heartbeat before the Call Directory list is cleared.
    public static var lcidEntitlementApply: (@Sendable (Bool) async -> Void)?

    /// Store a lapse or a return, then update metering.
    ///
    /// `false` persists the flag, sends one report with the feature off, and
    /// clears the Call Directory list. A later launch cannot turn billing back on.
    /// `true` allows reports again. The report uses the real extension state.
    public static func setEntitled(_ entitled: Bool) async {
        #if os(iOS)
        StoredEntitlement.write(entitled, appGroupID: CallDirectory.configuredAppGroup())
        setMetering(featureEnabled: entitled)
        // The Call Directory extension compiles this file without the host metering sources.
        #if !CALLERAPI_BRIDGING_ONLY
        if #available(iOS 13.0, *) {
            await DirectoryMetering.applyEntitlement(entitled)
        }
        if let apply = lcidEntitlementApply {
            await apply(entitled)
        }
        #endif
        if !entitled {
            await CallDirectory.clear()
        }
        #else
        StoredEntitlement.write(entitled)
        #endif
    }

    private static func setMetering(featureEnabled: Bool) {
        shared.queue.async {
            var idfv: String? = nil
            #if canImport(UIKit)
            idfv = UIDevice.current.identifierForVendor?.uuidString
            #endif
            let feat: Int32 = featureEnabled ? 1 : 0
            if let idfv = idfv {
                idfv.withCString { callerapi_set_metering($0, feat, 0) }
            } else {
                callerapi_set_metering(nil, feat, 0)
            }
        }
    }

    /// Privacy-preserving spam check (k-anon). May fetch a bucket on a cache
    /// miss, so it is asynchronous.
    public static func isSpam(_ phone: String) async throws -> Bool {
        try await shared.run {
            shared.ensureInitialisedLocked()
            return callerapi_is_spam(phone) == 1
        }
    }

    /// Privacy-preserving business-label lookup (k-anon). Returns the caller's
    /// business name, or nil if the number is not a known business.
    public static func lookupLabel(_ phone: String) async throws -> String? {
        try await shared.runThrowing { () -> String? in
            shared.ensureInitialisedLocked()
            var buf = [CChar](repeating: 0, count: 256)
            let rc = callerapi_lookup_label(phone, &buf, Int32(buf.count))
            if rc == 0 { return String(cString: buf) }
            if rc == -8 /* NOTFOUND */ { return nil }
            throw CallerAPIError(code: rc)
        }
    }

    /// Force a metering check-in now (otherwise runs via BackgroundSync).
    @discardableResult
    public static func checkIn() async -> Bool {
        if !isEntitled() { return false }
        return await withCheckedContinuation { cont in
            shared.queue.async {
                shared.ensureInitialisedLocked()
                cont.resume(returning: callerapi_checkin() == 0)
            }
        }
    }

    // MARK: - Instance helpers

    private func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(returning: work()) }
        }
    }

    private func runThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do { cont.resume(returning: try work()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}

// MARK: - Configuration

/// Credentials and timeouts for ``CallerAPI/configure(_:featureEnabled:)``.
///
/// Copy `sdkKey` and `sdkSecret` from the CallerAPI dashboard. They identify your
/// app to the lookup service, and every lookup is billed to them.
///
/// There is no client key here. On iOS the metering key belongs to Live Caller ID
/// and is passed to `CallerAPILiveCallerID.bootstrap` instead.
public struct CallerAPIConfig: Sendable {
    /// SDK key from the dashboard. Identifies your app.
    public var sdkKey: String?
    /// HMAC signing secret paired with ``sdkKey``. Keep it out of source control.
    public var sdkSecret: String?
    /// API origin override, for a regional or staging endpoint.
    public var apiBase: String?
    /// Budget for a lookup that can land near the call path.
    public var lookupTimeoutMs: Int32
    /// Budget for background transfers.
    public var networkTimeoutMs: Int32

    public init(
        sdkKey: String? = nil,
        sdkSecret: String? = nil,
        apiBase: String? = nil,
        lookupTimeoutMs: Int32 = 2_500,
        networkTimeoutMs: Int32 = 30_000
    ) {
        self.sdkKey = sdkKey
        self.sdkSecret = sdkSecret
        self.apiBase = apiBase
        self.lookupTimeoutMs = lookupTimeoutMs
        self.networkTimeoutMs = networkTimeoutMs
    }

    /// Reads the credentials from the app's Info.plist.
    ///
    /// This is the iOS counterpart of the Android manifest meta-data, and the only
    /// credential source available to the Flutter and React Native bridges, which
    /// call the lookup methods directly. Keys:
    ///
    /// - `CallerAPISDKKey`
    /// - `CallerAPISDKSecret`
    /// - `CallerAPIAPIBase` (optional)
    public static func fromInfoPlist(_ bundle: Bundle = .main) -> CallerAPIConfig {
        func string(_ key: String) -> String? {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // A build setting that never got substituted leaves the placeholder
            // behind, which is worse than absent: it reaches the server as a
            // credential and fails there instead of here.
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
            return trimmed
        }
        return CallerAPIConfig(
            sdkKey: string("CallerAPISDKKey"),
            sdkSecret: string("CallerAPISDKSecret"),
            apiBase: string("CallerAPIAPIBase")
        )
    }
}

// MARK: - Error

public struct CallerAPIError: LocalizedError, Sendable {
    public let code: Int32

    init(code: Int32) { self.code = code }

    public var errorDescription: String? {
        switch code {
        case -1: return "CallerAPI: not initialised"
        case -2: return "CallerAPI: authentication failed"
        case -3: return "CallerAPI: network error"
        case -4: return "CallerAPI: crypto error"
        case -5: return "CallerAPI: parse error"
        case -6: return "CallerAPI: I/O error"
        case -7: return "CallerAPI: session expired"
        case -8: return "CallerAPI: not found"
        case -9: return "CallerAPI: busy, answer unknown"
        case -10: return "CallerAPI: no credentials — set CallerAPISDKKey and "
            + "CallerAPISDKSecret in Info.plist, or pass CallerAPIConfig to configure"
        default: return "CallerAPI: unknown error (\(code))"
        }
    }
}

// MARK: - Helpers

private func cacheDirectory() -> String {
    let fm = FileManager.default
    let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let dir = caches.appendingPathComponent("CallerAPI")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
}
