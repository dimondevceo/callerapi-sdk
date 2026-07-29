import XCTest
@testable import CallerAPILiveCallerID

// These exercise the Foundation-only configuration + App Group token-sharing
// logic, which is the only host-app-facing behavior we can verify off-device.
// The call-time Live Caller ID Lookup path is run by iOS and is covered by the
// on-device manual checklist in the Example app, not here.

final class ConfigurationTests: XCTestCase {

    func testProductionDefaults() {
        let p = CallerAPILiveCallerIDConfiguration.production
        // Apple requires bare subdomains (no path, no port, no trailing slash)
        // for the service + issuer URLs; path-style was dropped in iOS 26.4.
        XCTAssertEqual(p.serviceURL.absoluteString, "https://pir.callerapi.com")
        XCTAssertEqual(p.tokenIssuerURL.absoluteString, "https://pat.callerapi.com")
        XCTAssertNil(p.serviceURL.port, "non-standard ports are rejected by Apple")
        XCTAssertNil(p.tokenIssuerURL.port, "non-standard ports are rejected by Apple")
        XCTAssertEqual(p.serviceURL.scheme, "https")
        XCTAssertEqual(p.tokenIssuerURL.scheme, "https")
        XCTAssertFalse(p.serviceURL.absoluteString.hasSuffix("/"),
                       "trailing slash is rejected by Apple's onboarding checks")
        XCTAssertFalse(p.tokenIssuerURL.absoluteString.hasSuffix("/"),
                       "trailing slash is rejected by Apple's onboarding checks")
        XCTAssertEqual(p.serviceURL.path, "", "service URL must be a bare subdomain (no path)")
        XCTAssertEqual(p.tokenIssuerURL.path, "", "issuer URL must be a bare subdomain (no path)")
        XCTAssertEqual(p.userTierToken, Data("callerapi-tier-default".utf8))
        XCTAssertFalse(p.userTierToken.isEmpty, "default tier token must be non-empty")
    }

    func testInitAssignsFields() {
        let svc = URL(string: "https://staging.example.com/api/pir")!
        let iss = URL(string: "https://staging.example.com/api/pat")!
        let tok = Data("tok".utf8)
        let c = CallerAPILiveCallerIDConfiguration(serviceURL: svc, tokenIssuerURL: iss, userTierToken: tok)
        XCTAssertEqual(c.serviceURL, svc)
        XCTAssertEqual(c.tokenIssuerURL, iss)
        XCTAssertEqual(c.userTierToken, tok)
    }

    func testEquatable() {
        XCTAssertEqual(.production, CallerAPILiveCallerIDConfiguration.production)
        var other = CallerAPILiveCallerIDConfiguration.production
        other.userTierToken = Data("different".utf8)
        XCTAssertNotEqual(.production, other)
    }
}

final class SharedStoreTests: XCTestCase {

    private var suite: String!

    override func setUp() {
        super.setUp()
        // A unique suite name per test so cases never see each other's writes.
        suite = "test.callerapi.lcid.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let suite { UserDefaults().removePersistentDomain(forName: suite) }
        suite = nil
        super.tearDown()
    }

    func testNilAppGroupReturnsProduction() {
        XCTAssertEqual(SharedStore.load(appGroup: nil), .production)
    }

    func testUnwrittenSuiteReturnsProduction() {
        XCTAssertEqual(SharedStore.load(appGroup: suite), .production)
    }

    func testUserTierTokenRoundTrips() {
        let token = Data("user-123-token".utf8)
        SharedStore.setUserTierToken(token, appGroup: suite)
        let loaded = SharedStore.load(appGroup: suite)
        XCTAssertEqual(loaded.userTierToken, token)
        // URLs untouched → still production.
        XCTAssertEqual(loaded.serviceURL, CallerAPILiveCallerIDConfiguration.defaultServiceURL)
        XCTAssertEqual(loaded.tokenIssuerURL, CallerAPILiveCallerIDConfiguration.defaultTokenIssuerURL)
    }

    func testEmptyTokenIsIgnored() {
        SharedStore.setUserTierToken(Data(), appGroup: suite)
        // An empty override must fall back to the bundled default, never an
        // empty token (which the issuer would reject).
        XCTAssertEqual(SharedStore.load(appGroup: suite).userTierToken,
                       CallerAPILiveCallerIDConfiguration.defaultUserTierToken)
    }

    func testEndpointOverridesRoundTrip() {
        let svc = URL(string: "https://staging.example.com/api/pir")!
        let iss = URL(string: "https://staging.example.com/api/pat")!
        SharedStore.setEndpoints(serviceURL: svc, tokenIssuerURL: iss, appGroup: suite)
        let loaded = SharedStore.load(appGroup: suite)
        XCTAssertEqual(loaded.serviceURL, svc)
        XCTAssertEqual(loaded.tokenIssuerURL, iss)
    }

    func testResetClearsOverrides() {
        SharedStore.setUserTierToken(Data("t".utf8), appGroup: suite)
        SharedStore.setEndpoints(serviceURL: URL(string: "https://s.example.com")!,
                                 tokenIssuerURL: nil, appGroup: suite)
        SharedStore.reset(appGroup: suite)
        XCTAssertEqual(SharedStore.load(appGroup: suite), .production)
    }

    func testEffectiveConfigurationUsesAppGroupOverride() {
        let token = Data("via-public-api".utf8)
        SharedStore.setUserTierToken(token, appGroup: suite)
        CallerAPILiveCallerID.appGroupIdentifier = suite
        defer { CallerAPILiveCallerID.appGroupIdentifier = nil }
        XCTAssertEqual(CallerAPILiveCallerID.effectiveConfiguration.userTierToken, token)
    }
}
