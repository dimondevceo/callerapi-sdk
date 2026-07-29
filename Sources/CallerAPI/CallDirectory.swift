#if os(iOS)
import Foundation
import CallKit
import Security
// SPM exposes the C core as a module; the drag-and-drop path uses the bridging
// header instead (so the module is absent there) - hence the canImport guard.
#if canImport(CallerAPICCore)
import CallerAPICCore
#endif

/// Legacy-iOS (13-17) spam **blocking** via a CallKit Call Directory extension.
///
/// iOS does not allow a per-call network lookup before iOS 18, so older devices
/// can only block from a **pre-loaded local list** that a Call Directory
/// extension hands to CallKit. This type fetches that list privately (the
/// download is an opaque encrypted blob) and keeps it encrypted on disk:
///
///   * Host app: call ``sync()`` (e.g. at launch and from a background refresh)
///     to download the latest blocklist and ask CallKit to reload the extension.
///   * Extension: call ``load(into:)`` from `beginRequest(with:)` to decrypt the
///     on-disk blob and feed the numbers to CallKit.
///
/// Both processes share the encrypted blob through an **App Group** container and
/// share the at-rest decryption key through a **Keychain access group**. Set both
/// on the host and the extension target (entitlements), then `configure(_:)` with
/// the matching identifiers in both processes.
///
/// On iOS 18+ prefer Live Caller ID Lookup (the `ios-lcid` SDK), which does real
/// per-call private blocking. Use this Call Directory path only as the iOS 13-17
/// fallback.
///
/// ```swift
/// // Host app (e.g. in AppDelegate):
/// CallerAPI.CallDirectory.configure(.init(
///     appGroup: "group.com.yourco.app",
///     extensionBundleID: "com.yourco.app.CallDirectory",
///     keychainAccessGroup: "$(AppIdentifierPrefix)com.yourco.app.shared"))
/// CallerAPI.CallDirectory.scheduleDeferredSync(after: 60)
/// ```
public extension CallerAPI {

    enum CallDirectory {

        /// Identifiers that must match between the host app and the extension.
        public struct Config: Sendable {
            /// App Group id shared by host + extension (entitlement
            /// `com.apple.security.application-groups`). The encrypted blocklist
            /// blob lives in this group's container.
            public let appGroup: String
            /// The Call Directory extension's bundle id (used to reload it).
            public let extensionBundleID: String
            /// Keychain access group shared by host + extension
            /// (`<TeamID>.<shared-group>`). Required so the extension can read
            /// the at-rest key the host created. Pass `nil` only if host and
            /// extension somehow share the default group (rare).
            public let keychainAccessGroup: String?
            /// File name for the encrypted blob inside the App Group container.
            public let blobFileName: String

            public init(appGroup: String,
                        extensionBundleID: String,
                        keychainAccessGroup: String? = nil,
                        blobFileName: String = "callerapi-blocklist.bin") {
                self.appGroup = appGroup
                self.extensionBundleID = extensionBundleID
                self.keychainAccessGroup = keychainAccessGroup
                self.blobFileName = blobFileName
            }
        }

        private static let lock = NSLock()
        private static var _config: Config?

        /// Set the shared identifiers. Call once per process before `sync()` /
        /// `load(into:)` (host AND extension must configure with equal values).
        public static func configure(_ config: Config) {
            lock.lock(); _config = config; lock.unlock()
        }

        // MARK: - Host app

        /// Schedule blocklist download after a delay so it does not race LCID prewarm.
        public static func scheduleDeferredSync(after delay: TimeInterval) {
            guard delay > 0 else { return }
            Task.detached(priority: .utility) {
                let ns = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                try? await sync()
            }
        }

        /// Download the latest encrypted blocklist. Avoid calling on cold launch —
        /// use ``scheduleDeferredSync`` or ``CallerAPILiveCallerID/bootstrap(_:)``.
        public static func sync() async throws {
            _ = CallerAPI.shared            // ensure the C core is initialised
            let c = try currentConfig()

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let key = try deviceKey(c)
                        let path = try blobURL(c).path
                        let rc = key.withUnsafeBufferPointer { ptr in
                            callerapi_calldir_sync(ptr.baseAddress, path)
                        }
                        guard rc == 0 else { throw CallerAPIError(code: rc) }
                        cont.resume(returning: ())
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }

            try await reloadExtension(c.extensionBundleID)
        }

        private static func reloadExtension(_ identifier: String) async throws {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: identifier) { error in
                    if let error = error { cont.resume(throwing: error) }
                    else { cont.resume(returning: ()) }
                }
            }
        }

        // MARK: - Extension

        /// Decrypt the on-disk blob and add every number as a CallKit blocking
        /// entry. Call from the extension's `beginRequest(with:)`. Offline: no
        /// network or session is used, so it is safe in the constrained
        /// Call Directory extension sandbox.
        public static func load(into context: CXCallDirectoryExtensionContext) throws {
            let c = try currentConfig()
            let key = try deviceKey(c)
            let path = try blobURL(c).path

            // We always have the full current list, so do a full refresh.
            if context.isIncremental {
                context.removeAllBlockingEntries()
            }

            final class Sink {
                let ctx: CXCallDirectoryExtensionContext
                init(_ ctx: CXCallDirectoryExtensionContext) { self.ctx = ctx }
            }
            let sink = Sink(context)
            let user = Unmanaged.passUnretained(sink).toOpaque()

            let cb: @convention(c) (Int64, UnsafeMutableRawPointer?) -> Void = { number, user in
                guard let user = user else { return }
                let sink = Unmanaged<Sink>.fromOpaque(user).takeUnretainedValue()
                // The C core emits numbers strictly ascending, as CallKit needs.
                sink.ctx.addBlockingEntry(withNextSequentialPhoneNumber: number)
            }

            let rc = key.withUnsafeBufferPointer { ptr in
                callerapi_calldir_load(ptr.baseAddress, path, cb, user)
            }
            guard rc == 0 else { throw CallerAPIError(code: rc) }
        }

        // MARK: - Internals

        private static func currentConfig() throws -> Config {
            lock.lock(); defer { lock.unlock() }
            guard let c = _config else { throw CallerAPIError(code: -1) }
            return c
        }

        private static func blobURL(_ c: Config) throws -> URL {
            guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: c.appGroup) else {
                throw CallerAPIError(code: -6)   // app group not configured
            }
            return container.appendingPathComponent(c.blobFileName)
        }

        /// Fetch (or, on first run, create) the 32-byte at-rest device key from
        /// the Keychain. Stored with `AfterFirstUnlock` so the extension can read
        /// it during an incoming call even when the host app is not running.
        static func deviceKey(_ c: Config) throws -> [UInt8] {
            let service = "com.callerapi.calldir.devicekey"
            let account = "default"

            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            if let ag = c.keychainAccessGroup {
                query[kSecAttrAccessGroup as String] = ag
            }

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data, data.count == 32 {
                return [UInt8](data)
            }
            guard status == errSecItemNotFound else {
                throw CallerAPIError(code: -6)   // keychain read failed
            }

            var key = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, key.count, &key) == errSecSuccess else {
                throw CallerAPIError(code: -4)
            }

            var add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: Data(key),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            if let ag = c.keychainAccessGroup {
                add[kSecAttrAccessGroup as String] = ag
            }

            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                // Another process created it first; read it back.
                var ritem: CFTypeRef?
                if SecItemCopyMatching(query as CFDictionary, &ritem) == errSecSuccess,
                   let data = ritem as? Data, data.count == 32 {
                    return [UInt8](data)
                }
                throw CallerAPIError(code: -6)
            }
            guard addStatus == errSecSuccess else {
                throw CallerAPIError(code: -6)
            }
            return key
        }
    }
}
#endif
