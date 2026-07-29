import Foundation
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
/// CallerAPI.configure(featureEnabled: true)
/// let spam  = try await CallerAPI.isSpam("+1234567890")
/// let label = try await CallerAPI.lookupLabel("+1234567890")
/// ```
public final class CallerAPI: @unchecked Sendable {

    /// Shared singleton.
    public static let shared = CallerAPI()

    private let queue = DispatchQueue(label: "com.callerapi.sdk", qos: .userInitiated)
    private var initialised = false

    private init() {
        initialise()
    }

    // MARK: - Lifecycle

    private func initialise() {
        queue.sync {
            guard !initialised else { return }
            let dir = cacheDirectory()
            let rc = callerapi_init(dir)
            initialised = (rc == 0)
        }
    }

    deinit {
        callerapi_cleanup()
    }

    // MARK: - Public API (static convenience)

    /// Configure metering for MAU/billing: reports the stable per-vendor device
    /// id (IDFV) and whether the spam feature is enabled. Call once at launch.
    public static func configure(featureEnabled: Bool = true) {
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
        try await shared.run { callerapi_is_spam(phone) == 1 }
    }

    /// Privacy-preserving business-label lookup (k-anon). Returns the caller's
    /// business name, or nil if the number is not a known business.
    public static func lookupLabel(_ phone: String) async throws -> String? {
        try await shared.runThrowing { () -> String? in
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
        await withCheckedContinuation { cont in
            shared.queue.async {
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
