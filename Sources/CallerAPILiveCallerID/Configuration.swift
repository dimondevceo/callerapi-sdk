import Foundation

/// Connection parameters the iOS system needs to run Live Caller ID Lookup
/// against the CallerAPI backend.
///
/// These map 1:1 onto the three arguments of Apple's
/// `LiveCallerIDLookupExtensionContext(serviceURL:tokenIssuerURL:userTierToken:)`.
///
/// Apple requires the service URL and token issuer URL to be **bare
/// subdomains** (no paths, no ports, no trailing slash) for apps installed
/// from the App Store / TestFlight — path-style URLs were dropped in
/// iOS/macOS 26.4. Xcode dev installs do not enforce this.
///
/// - `serviceURL`: the PIR origin. The system appends `/config`, `/key` and
///   `/queries` to it. CallerAPI serves these at `https://pir.callerapi.com`.
/// - `tokenIssuerURL`: the Privacy Pass issuer. The system appends
///   `/.well-known/private-token-issuer-directory` (and
///   `/token-key-for-user-token`) and posts to the directory's
///   `issuer-request-uri`. CallerAPI serves these at `https://pat.callerapi.com`.
/// - `userTierToken`: an opaque HTTP bearer token identifying the *tier* of the
///   person using the host app. The CallerAPI issuer is currently single-tier
///   and accepts any non-empty token, so the bundled default works out of the
///   box; set a per-user token via ``CallerAPILiveCallerID/setUserTierToken(_:)``
///   once your app authenticates the user.
public struct CallerAPILiveCallerIDConfiguration: Sendable, Equatable {

    /// PIR origin. The system appends `/config`, `/key`, `/queries`.
    public var serviceURL: URL

    /// Privacy Pass token issuer base URL.
    public var tokenIssuerURL: URL

    /// Per-user HTTP bearer token presented to the token issuer.
    public var userTierToken: Data

    public init(serviceURL: URL, tokenIssuerURL: URL, userTierToken: Data) {
        self.serviceURL = serviceURL
        self.tokenIssuerURL = tokenIssuerURL
        self.userTierToken = userTierToken
    }

    // MARK: - Production defaults

    /// CallerAPI production PIR origin (bare subdomain, per Apple's onboarding
    /// requirements). The system fetches `…/config`, uploads keys to `…/key`,
    /// and queries `…/queries`.
    public static let defaultServiceURL = URL(string: "https://pir.callerapi.com")!

    /// CallerAPI production Privacy Pass issuer (bare subdomain). The system
    /// fetches `…/.well-known/private-token-issuer-directory` and issues tokens
    /// at the directory's `issuer-request-uri` (`…/issue`).
    public static let defaultTokenIssuerURL = URL(string: "https://pat.callerapi.com")!

    /// Default tier token. The CallerAPI issuer is single-tier and only
    /// presence-checks this value, so a fixed non-empty token authenticates
    /// every device until a real per-user token is configured.
    public static let defaultUserTierToken = Data("callerapi-tier-default".utf8)

    /// The all-defaults production configuration (zero-config).
    public static let production = CallerAPILiveCallerIDConfiguration(
        serviceURL: defaultServiceURL,
        tokenIssuerURL: defaultTokenIssuerURL,
        userTierToken: defaultUserTierToken
    )

    // MARK: - Info.plist keys

    /// Info.plist key holding a service URL that replaces ``defaultServiceURL``.
    public static let serviceURLInfoPlistKey = "CallerAPILCIDServiceURL"

    /// Info.plist key holding a token issuer URL that replaces
    /// ``defaultTokenIssuerURL``.
    public static let tokenIssuerURLInfoPlistKey = "CallerAPILCIDTokenIssuerURL"

    /// Reads endpoint overrides from a bundle's Info.plist.
    ///
    /// A customer whose Apple registration uses a dedicated host set needs its
    /// own two URLs. Before 1.4.0 the only way to supply them was a Swift call
    /// to `setEndpoints`, which Flutter and React Native never exposed, so those
    /// customers needed a per-customer build of the SDK. Two Info.plist keys
    /// replace that: the same build serves every customer.
    ///
    /// Returns nil when neither key is present, which keeps the shared hosts as
    /// the default for everybody else.
    ///
    /// Read `Bundle.main` from the extension and you get the extension's own
    /// Info.plist, because the extension is a separate process. Read it from the
    /// host app and you get the host's. Setting the keys on either one works.
    /// ``CallerAPILiveCallerID/bootstrap(_:)`` copies the host's values into the
    /// App Group so the extension sees them without its own copy.
    public static func endpointOverrides(
        in bundle: Bundle = .main
    ) -> (serviceURL: URL?, tokenIssuerURL: URL?)? {
        func url(_ key: String) -> URL? {
            guard
                let raw = bundle.object(forInfoDictionaryKey: key) as? String,
                !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                url.scheme?.lowercased() == "https"
            else {
                return nil
            }
            return url
        }
        let service = url(serviceURLInfoPlistKey)
        let issuer = url(tokenIssuerURLInfoPlistKey)
        guard service != nil || issuer != nil else { return nil }
        return (service, issuer)
    }
}
