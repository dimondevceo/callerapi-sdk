import XCTest
@testable import CallerAPILiveCallerID

final class EntitlementPolicyTests: XCTestCase {

    func testMissingValueMeansEntitled() {
        let name = suiteName()
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertTrue(MeteringEntitlement.isEntitled(in: defaults))
        XCTAssertEqual(MeteringEntitlement.key, "com.callerapi.sdk.entitled")
    }

    func testLapsePersistsAcrossRelaunch() {
        let name = suiteName()
        let groupName = name + ".group"
        let first = UserDefaults(suiteName: name)!
        let group = UserDefaults(suiteName: groupName)!
        first.removePersistentDomain(forName: name)
        group.removePersistentDomain(forName: groupName)

        MeteringEntitlement.write(false, defaults: first, appGroup: group)

        let relaunch = UserDefaults(suiteName: name)!
        let relaunchGroup = UserDefaults(suiteName: groupName)!
        XCTAssertFalse(MeteringEntitlement.isEntitled(in: relaunch))
        XCTAssertFalse(MeteringEntitlement.isEntitled(in: relaunchGroup))
    }

    func testReturnPersistsAcrossRelaunch() {
        let name = suiteName()
        let first = UserDefaults(suiteName: name)!
        first.removePersistentDomain(forName: name)
        MeteringEntitlement.write(false, defaults: first)
        MeteringEntitlement.write(true, defaults: first)
        let relaunch = UserDefaults(suiteName: name)!
        XCTAssertTrue(MeteringEntitlement.isEntitled(in: relaunch))
    }

    func testLapseHeartbeatIsFalseAndLaterHeartbeatsStop() {
        XCTAssertEqual(
            HeartbeatPlan.next(
                configured: true,
                meteringEnabled: true,
                entitled: false,
                extensionsOn: true,
                forceOff: true
            ),
            .send(featureEnabled: false)
        )
        XCTAssertEqual(
            HeartbeatPlan.next(
                configured: true,
                meteringEnabled: false,
                entitled: false,
                extensionsOn: true,
                forceOff: false
            ),
            .skip
        )
        XCTAssertFalse(HeartbeatPlan.allowsPeriodicHeartbeat(entitled: false, meteringEnabled: true))
        XCTAssertFalse(HeartbeatPlan.allowsPeriodicHeartbeat(entitled: true, meteringEnabled: false))
    }

    func testEntitledHeartbeatUsesExtensionState() {
        XCTAssertEqual(
            HeartbeatPlan.next(
                configured: true,
                meteringEnabled: true,
                entitled: true,
                extensionsOn: true,
                forceOff: false
            ),
            .send(featureEnabled: true)
        )
        XCTAssertEqual(
            HeartbeatPlan.next(
                configured: true,
                meteringEnabled: true,
                entitled: true,
                extensionsOn: false,
                forceOff: false
            ),
            .send(featureEnabled: false)
        )
        XCTAssertEqual(
            HeartbeatPlan.next(
                configured: false,
                meteringEnabled: true,
                entitled: true,
                extensionsOn: true,
                forceOff: true
            ),
            .skip
        )
    }

    func testLapseSkipsCallDirectorySync() {
        XCTAssertFalse(HeartbeatPlan.allowsCallDirectorySync(entitled: false))
        XCTAssertTrue(HeartbeatPlan.allowsCallDirectorySync(entitled: true))
    }

    func testVendorIDStaysOneDevice() {
        XCTAssertEqual(DeviceIdentity.fallbackKey, "com.callerapi.lcid.deviceid")
        let name = suiteName()
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let idfv = "11111111-2222-3333-4444-555555555555"
        XCTAssertEqual(DeviceIdentity.resolve(vendorID: idfv, defaults: defaults), idfv)
        let again = UserDefaults(suiteName: name)!
        XCTAssertEqual(DeviceIdentity.resolve(vendorID: idfv, defaults: again), idfv)

        let fallbackName = suiteName()
        let cold = UserDefaults(suiteName: fallbackName)!
        cold.removePersistentDomain(forName: fallbackName)
        let first = DeviceIdentity.resolve(vendorID: nil, defaults: cold)
        let second = DeviceIdentity.resolve(vendorID: nil, defaults: UserDefaults(suiteName: fallbackName)!)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, idfv)
    }

    func testFallbackUUIDStaysWhenVendorIDAppearsLater() {
        let name = suiteName()
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let first = DeviceIdentity.resolve(vendorID: nil, defaults: defaults)
        let idfv = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let second = DeviceIdentity.resolve(
            vendorID: idfv,
            defaults: UserDefaults(suiteName: name)!
        )
        XCTAssertEqual(second, first)
        XCTAssertNotEqual(second, idfv)
    }

    private func suiteName() -> String {
        "com.callerapi.test.\(UUID().uuidString)"
    }
}
