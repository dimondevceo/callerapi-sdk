// The host-app and extension APIs are iOS-only, so this file cannot compile for
// the macOS host that `swift test` targets. CI type-checks it for a real iOS
// target with `xcodebuild build-for-testing`.
#if os(iOS)
import Foundation
import XCTest

// A plain import, deliberately not `@testable`: this file must see only what a
// host app sees. Members of a `public extension` are public by default, so it is
// easy to move one into an internal extension and not notice that the integration
// guide now tells customers to call something they cannot reach. Compiling this
// file is the check.
import CallerAPILiveCallerID

@available(iOS 18.0, *)
final class PublicSurfaceTests: XCTestCase {

    /// Every call the host-app integration guide asks a customer to write.
    func testHostIntegrationAPIIsReachableFromOutsideTheModule() {
        // Not executed. Type-checking this closure is the assertion.
        let _: () -> Void = {
            CallerAPILiveCallerID.bootstrap(.init(
                extensionIdentifier: "com.example.app.LiveLookup",
                lcidClientKey: "client-key",
                heartbeatTaskIdentifier: "com.example.app.lcid.heartbeat",
                appGroupIdentifier: "group.com.example.app"
            ))
            CallerAPILiveCallerID.configureMetering(clientKey: "client-key")
            Task { await CallerAPILiveCallerID.applyEntitlement(false) }
            CallerAPILiveCallerID.appGroupIdentifier = "group.com.example.app"
            CallerAPILiveCallerID.setUserTierToken(Data())
            _ = CallerAPILiveCallerID.isDisabled(forExtensionWithIdentifier: "x")
            _ = CallerAPILiveCallerID.isTransientExtensionError(
                NSError(domain: "com.apple.extensionKit.errorDomain", code: 2)
            )
            _ = CallerAPILiveCallerID.effectiveConfiguration
            Task {
                _ = await CallerAPILiveCallerID.waitUntilEnabled(forExtensionWithIdentifier: "x")
                try await CallerAPILiveCallerID.reset(forExtensionWithIdentifier: "x")
                try await CallerAPILiveCallerID.refreshExtensionContext(forExtensionWithIdentifier: "x")
                try await CallerAPILiveCallerID.reprovision(
                    forExtensionWithIdentifier: "x",
                    clearCachedLookups: true
                )
            }
        }
        XCTAssertFalse(CallerAPILiveCallerID.sdkVersion.isEmpty)
    }

    /// The extension target's only job, from the template we ship.
    func testExtensionFactoryIsReachableFromOutsideTheModule() {
        let _: () -> Void = {
            _ = CallerAPILiveCallerID.makeExtensionContext()
        }
    }
}
#endif
