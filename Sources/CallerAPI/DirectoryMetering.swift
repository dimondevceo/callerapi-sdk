#if os(iOS)
import Foundation
import UIKit
import CallKit
import BackgroundTasks

// sdk/scripts/check-sdk-versions.sh requires this assignment to match sdk/VERSION.
private let directoryMeteringSDKVersion = "1.8.0"

/// Same decision as `HeartbeatPlan.next`. Keep the two copies identical.
private enum DirectoryHeartbeatPlan {
    case skip
    case send(featureEnabled: Bool)

    static func next(
        configured: Bool,
        meteringEnabled: Bool,
        entitled: Bool,
        extensionsOn: Bool,
        forceOff: Bool
    ) -> DirectoryHeartbeatPlan {
        if !configured { return .skip }
        if !forceOff && !meteringEnabled { return .skip }
        if forceOff || !entitled { return .send(featureEnabled: false) }
        return .send(featureEnabled: extensionsOn)
    }
}

/// Same id as `DeviceIdentity` on the Live Caller ID path.
/// The fallback key must stay `com.callerapi.lcid.deviceid`.
/// Keep this resolve function identical to `DeviceIdentity.resolve`.
private enum HostDeviceIdentity {
    static let fallbackKey = "com.callerapi.lcid.deviceid"

    static func resolve(vendorID: String?, defaults: UserDefaults) -> String {
        // Once a fallback UUID is issued, keep it. A later vendor id would bill this phone twice.
        if let cached = defaults.string(forKey: fallbackKey), !cached.isEmpty {
            return cached
        }
        if let vendorID = vendorID, !vendorID.isEmpty { return vendorID }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: fallbackKey)
        return generated
    }
}

private final class DirectoryMeteringStore: @unchecked Sendable {
    static let shared = DirectoryMeteringStore()

    private let lock = NSLock()
    private var clientKey: String?
    private var callDirectoryExtensionID: String?
    private var endpoint = URL(string: "https://api.callerapi.com/api/lcid/heartbeat")!
    private var enabled = false
    private var taskIdentifier: String?
    private var registeredTasks = Set<String>()

    private init() {}

    func configure(clientKey: String, callDirectoryExtensionID: String, endpoint: URL?, enabled: Bool) {
        lock.lock()
        self.clientKey = clientKey
        self.callDirectoryExtensionID = callDirectoryExtensionID
        if let endpoint { self.endpoint = endpoint }
        self.enabled = enabled
        lock.unlock()
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        lock.unlock()
    }

    func snapshot() -> (key: String?, extensionID: String?, endpoint: URL, enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (clientKey, callDirectoryExtensionID, endpoint, enabled)
    }

    func setTaskIdentifier(_ identifier: String) {
        lock.lock()
        taskIdentifier = identifier
        lock.unlock()
    }

    func taskID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return taskIdentifier
    }

    func claimTask(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return registeredTasks.insert(identifier).inserted
    }
}

/// Usage report for Call Directory on iOS 13 and later.
///
/// Live Caller ID keeps its own report on iOS 18 when that extension is present.
/// Both reports use `identifierForVendor` and the same fallback key, so one phone
/// is one device after an upgrade.
@available(iOS 13.0, *)
public extension CallerAPI {

    enum DirectoryMetering {

        /// Store the client key and send the first report.
        /// Registers the background task when `heartbeatTaskIdentifier` is set.
        public static func start(
            clientKey: String,
            callDirectoryExtensionID: String,
            heartbeatTaskIdentifier: String? = nil,
            endpoint: URL? = nil
        ) {
            let trimmed = clientKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let extensionID = callDirectoryExtensionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !extensionID.isEmpty else { return }

            let store = DirectoryMeteringStore.shared
            store.configure(
                clientKey: trimmed,
                callDirectoryExtensionID: extensionID,
                endpoint: endpoint,
                enabled: StoredEntitlement.isEntitled()
            )
            if let heartbeatTaskIdentifier = heartbeatTaskIdentifier, !heartbeatTaskIdentifier.isEmpty {
                store.setTaskIdentifier(heartbeatTaskIdentifier)
                registerBackground(heartbeatTaskIdentifier)
            }
            Task { await applyEntitlement(StoredEntitlement.isEntitled()) }
        }

        /// Send the report that matches the stored entitlement, then stop or resume.
        public static func applyEntitlement(_ entitled: Bool) async {
            let store = DirectoryMeteringStore.shared
            guard store.snapshot().key != nil else { return }
            if entitled {
                store.setEnabled(true)
                _ = try? await sendHeartbeat(forceOff: false)
                return
            }
            _ = try? await sendHeartbeat(forceOff: true)
            store.setEnabled(false)
        }

        private static func registerBackground(_ identifier: String) {
            let store = DirectoryMeteringStore.shared
            guard store.claimTask(identifier) else {
                scheduleNext(identifier)
                return
            }
            BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
                scheduleNext(identifier)
                let finished = DirectoryCompletion()
                let work = Task {
                    let allowed = StoredEntitlement.isEntitled() && store.snapshot().enabled
                    if allowed {
                        _ = try? await sendHeartbeat(forceOff: false)
                    }
                    if finished.claim() { task.setTaskCompleted(success: true) }
                }
                task.expirationHandler = {
                    work.cancel()
                    if finished.claim() { task.setTaskCompleted(success: false) }
                }
            }
            scheduleNext(identifier)
        }

        private static func scheduleNext(_ identifier: String) {
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
            try? BGTaskScheduler.shared.submit(request)
        }

        private static func sendHeartbeat(forceOff: Bool) async throws {
            let store = DirectoryMeteringStore.shared
            let snap = store.snapshot()
            let extensionsOn: Bool
            if let extensionID = snap.extensionID, snap.enabled, StoredEntitlement.isEntitled(), !forceOff {
                extensionsOn = await callDirectoryEnabled(extensionID)
            } else {
                extensionsOn = false
            }
            let plan = DirectoryHeartbeatPlan.next(
                configured: snap.key != nil,
                meteringEnabled: snap.enabled,
                entitled: StoredEntitlement.isEntitled(),
                extensionsOn: extensionsOn,
                forceOff: forceOff
            )
            guard case .send(let featureEnabled) = plan, let key = snap.key else { return }
            try await post(key: key, endpoint: snap.endpoint, featureEnabled: featureEnabled)
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

        private static func deviceID() async -> String {
            await MainActor.run {
                HostDeviceIdentity.resolve(
                    vendorID: UIDevice.current.identifierForVendor?.uuidString,
                    defaults: .standard
                )
            }
        }

        private static func osVersion() async -> String {
            await MainActor.run { UIDevice.current.systemVersion }
        }

        /// Call Directory metering does not send App Attest.
        /// That includes iOS 14 to 17 and an iOS 18 phone that only uses Call Directory.
        /// A client in enforce mode drops these reports, so those devices are not counted.
        private static func post(key: String, endpoint: URL, featureEnabled: Bool) async throws {
            let body: [String: Any] = [
                "device_id": await deviceID(),
                "bundle_id": Bundle.main.bundleIdentifier ?? "",
                "platform": "ios",
                "feature_enabled": featureEnabled,
                "sdk_version": directoryMeteringSDKVersion,
                "os_version": await osVersion(),
            ]
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "X-LCID-Client-Key")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 20
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
        }
    }
}

private final class DirectoryCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
#endif
