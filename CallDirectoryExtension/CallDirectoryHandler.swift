import CallKit
import os.log

class CallDirectoryHandler: CXCallDirectoryProvider, CXCallDirectoryExtensionContextDelegate {

    private let log = Logger(subsystem: AppConfig.callDirectoryExtensionBundleID, category: "CallDirectory")

    private static let config: CallerAPI.CallDirectory.Config = {
        let keychainGroup = Bundle.main.object(forInfoDictionaryKey: "CallerAPIKeychainAccessGroup") as? String
        return CallerAPI.CallDirectory.Config(
            appGroup: AppConfig.appGroup,
            extensionBundleID: AppConfig.callDirectoryExtensionBundleID,
            keychainAccessGroup: keychainGroup
        )
    }()

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self
        CallerAPI.CallDirectory.configure(Self.config)

        do {
            if try CallerAPI.CallDirectory.hasBlocklistBlob() {
                try CallerAPI.CallDirectory.load(into: context)
                log.info("Loaded blocklist into CallKit")
            } else {
                log.info("No blocklist blob yet — completing with empty list")
            }
        } catch {
            log.error("Call Directory load failed: \(error.localizedDescription, privacy: .public)")
            context.cancelRequest(withError: error)
            return
        }

        context.completeRequest()
    }

    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext,
                       withError error: Error) {
        log.error("Call Directory reload failed: \(error.localizedDescription, privacy: .public)")
    }
}
