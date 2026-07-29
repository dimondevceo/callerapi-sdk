# Changelog

All notable changes to the CallerAPI SDKs are documented here. This project
adheres to [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

- **MAJOR** - source-breaking public API changes.
- **MINOR** - backward-compatible additions.
- **PATCH** - backward-compatible fixes.

Every CallerAPI SDK shares one version number, held in `sdk/VERSION` and
enforced across every platform (and the server's advertised
`LCID_LATEST_SDK_VERSION`) by `sdk/scripts/check-sdk-versions.sh`. A release
publishes all four platforms from a single `sdk-v<version>` tag.

## [1.4.0]

Lookups did not work on iOS. The published pod carries no credentials, by design,
and the Swift API had no way to supply them, so every `lookupLabel` failed
authentication. This release adds the credential API that Android always had.

Upgrading is a version bump plus two lines telling the SDK who you are. See
`UPGRADING.md`.

### Added

- **iOS**: `CallerAPI.configure(_:)` taking a `CallerAPIConfig`, the counterpart of
  Android's `CallerAPIConfig`. Supply `sdkKey` and `sdkSecret` from the dashboard.
- **iOS**: credentials are also read from the app's Info.plist, from
  `CallerAPISDKKey` and `CallerAPISDKSecret`. This mirrors the Android manifest
  meta-data, and is what makes lookups work through Flutter and React Native. Those
  bridges call the lookup methods directly and have nowhere to pass a credential.
- **iOS**: `CallerAPI.CallDirectory.hasBlocklistBlob()`, to tell "the host app has
  not synced yet" from a real failure. The Call Directory template already called
  it. Cancelling the request instead makes iOS treat the extension as broken.
- **iOS**: the bundle identifier is now reported when the SDK authenticates, so the
  server can refuse a credential presented by an app it was not issued to. Android
  has always reported its package name and signing digest.

### Fixed

- **iOS**: the Call Directory extension template did not compile. It was missing
  `import CallerAPI` and called the `hasBlocklistBlob()` above, which did not exist.
  This was the first file a customer builds on that path.
- **iOS**: the Live Caller ID extension template under `ExtensionTemplates/` was
  missing `import CallerAPILiveCallerID`. The copy published in the mirror was
  already correct, so no released package was affected.
- **Dashboard**: every "start it" snippet on the SDK setup page called a function
  that does not exist, on all four platforms: `CallerAPI.init` on Android,
  `CallerAPILiveCallerID.configure(clientKey:)` on iOS, and an `initialize` on
  Flutter and React Native. They now show the real API.

### Internal

- `sdk/scripts/check-extension-templates.sh` type-checks every shipped iOS
  extension template in CI. `Package.swift` compiles `Sources/` only, so nothing
  ever compiled the files customers copy into their own projects.
- A public-surface test pins the Live Caller ID host API with a plain, non-testable
  import, so a symbol the integration guide tells customers to call cannot quietly
  become unreachable from outside the module.

## [1.3.1]

The 1.3.0 React Native and Flutter packages still expected to find the native SDK
copied into them by hand, the way the old partner archives delivered it. Installed
from npm or pub.dev there is nothing to copy, so this release changes where they
get it from: the same registries every other dependency comes from.

Upgrading is a version bump. No API changed.

### Fixed

- **Flutter**: `flutter pub add callerapi` produced a project that could not build
  for either platform. Android failed outright, telling you to "re-copy from a fresh
  partner zip"; iOS compiled the plugin against a core that was not in the package,
  so calls into it had no implementation. The plugin now resolves
  `com.callerapi:callerapi-sdk` from Maven Central and the `CallerAPI` pod from
  CocoaPods.
- **React Native**: the same Android failure, and on iOS a private 6.7 MB copy of
  the core bundled into the npm tarball. That copy was never rebuilt at release and
  no credential guard inspected it, so it drifted away from the core served
  elsewhere. Both platforms now resolve the published artifacts.
- **iOS core**: the shipped `CallerAPI.xcframework` predated SDK version reporting
  and was rebuilt. Devices running the core previously sent no version, which left
  the server unable to distinguish SDK versions or apply app-identity binding to
  that traffic.

### Added

- The iOS core is published for the first time, as the `CallerAPI` pod and a SwiftPM
  product alongside `CallerAPILiveCallerID`. One package, one tag, two products —
  see the README at
  [github.com/dimondevceo/callerapi-sdk](https://github.com/dimondevceo/callerapi-sdk).
  It has an iOS 13 floor; Live Caller ID still needs iOS 18 and is unchanged.

## [1.3.0]

Publishing to public registries made the SDK credential recoverable by anyone who
downloads a customer's app — that is inherent to shipping a client, not a flaw in
the packaging, and it was always true of the vendored archives too. This release
makes possession of a credential insufficient on its own.

Nothing here is required to upgrade. All of it is opt-in per client and defaults
to off, so an existing integration behaves exactly as it did on 1.2.0.

### Added - app identity

- Every SDK now reports the identity the operating system holds for the host app,
  and the server can refuse a credential presented by an app it was not issued to.
  Android reports its `applicationId` and signing-certificate SHA-256 (read from
  `PackageManager`, not from configuration); iOS reports its bundle identifier.
- Identity is checked on both `/api/mobile/auth` and `/api/lcid/heartbeat`.

### Added - device attestation

- **Android**: Play Integrity. Requires the host app to add
  `com.google.android.play:integrity` — it needs a Play Console cloud project bound
  to the app, so it cannot be a transitive dependency of ours. Without it,
  attestation reports nothing and the server decides what that means.
- **iOS**: App Attest. A Secure Enclave key is generated once per install, attested
  over a server-issued challenge, and used to sign every subsequent heartbeat.
  Unavailable on the simulator.
- Attestation material is only produced when the server asks for it, so a client
  with attestation off pays nothing for this.

### Added - server controls

- Per-client attestation modes: `off`, `monitor` (record what enforcing would
  break) and `enforce` (refuse).
- A per-client monthly active device ceiling, with alerting at 80%, 95% and 100%.
- Billing reconciliation against Privacy Pass issuance. A month whose token
  issuance does not agree with the active devices customers reported has its
  invoices generated but held unsent for review.

### Changed

- `app_version` on the authentication body now reports the real SDK version. It
  was previously hardcoded to `1.0.0`, which meant the server's version policy
  could never identify an outdated integration.
- `callerapi_config` gained `package_name`, `cert_sha256` and `app_version`. The
  struct is extended, not reordered, so existing initialisation is unaffected.

### Fixed

- The prebuilt Android native libraries are now checked against the modification
  time of the C sources, not only for the presence of the expected JNI symbols. A
  changed function *signature* keeps the symbol name, so the previous check could
  not see it and the mismatch surfaced as stack corruption at runtime.
- `sync-lcid-sources.sh` enumerates the canonical directory instead of a
  hardcoded file list. A new source file previously reached the SwiftPM package
  but not the React Native and Flutter copies.

## [1.2.0]

### Changed - distribution

- **The SDKs are published to their ecosystems' registries.** Upgrading is a
  version bump in your own manifest instead of a support email with an archive
  attached:

  | Platform | Install |
  | --- | --- |
  | Android | `implementation("com.callerapi:callerapi-sdk:1.2.0")` (Maven Central) |
  | iOS | `pod 'CallerAPILiveCallerID', '~> 1.2'`, or SwiftPM at tag `sdk-v1.2.0` |
  | React Native | `npm install @callerapi/react-native@1.2.0` |
  | Flutter | `flutter pub add callerapi` |

  The published artifacts contain no per-customer secrets. See
  `sdk/UPGRADING.md` for the migration from a vendored copy.

- **Credentials are supplied at runtime rather than compiled in.** One build of
  the SDK now serves every customer, which is what makes registry distribution
  possible. Pass them to `CallerAPI.register(...)` (Android), or declare them in
  your manifest; see `sdk/UPGRADING.md`. Builds with credentials baked in
  continue to work.

### Added

- `callerapi_init_ex()` / `nativeInitEx` — runtime configuration of API base,
  SDK key and secret, and per-request network timeouts.
- `callerapi_is_spam_cached()` / `CallerAPI.cachedSpamVerdict()` — a lookup that
  answers only from cache and never performs I/O, for use on latency-critical
  paths.
- `callerapi_prewarm()` / `CallerAPI.prewarmAsync()` — refreshes the cache off
  the call path.
- iOS: published through **CocoaPods** in addition to Swift Package Manager, so
  CocoaPods-based apps no longer need a vendored copy.

### Fixed - Android

- **Call screening no longer blocks on the network.** `onScreenCall` performed a
  synchronous lookup, so on a slow or unreachable network the system's screening
  timeout elapsed and the call rang through unscreened. The verdict is now read
  from cache and the refresh happens afterwards, off the call path.
- **Blocked-call counts were reported more than once.** The counter was cleared
  only after the next successful check-in, so a retry re-sent totals that had
  already been accepted and inflated the figures the account was billed on.
  Accounting is now exactly-once.
- **The server's heartbeat interval was ignored**, and the periodic worker was
  enqueued with `KEEP`, so an interval change never reached devices already in
  the field. The advertised cadence is now adopted via `UPDATE`.
- The heartbeat worker retries with backoff and gives up after a bounded number
  of attempts instead of retrying indefinitely.

### Fixed - native core

- **Concurrent use could crash.** The shared context and the libcurl handle had
  no lock, so a lookup from the call-screening thread racing a check-in from a
  worker corrupted state. All public entry points now serialize.
- Every HTTP request carries connect and total timeouts; previously a stalled
  connection could hang a caller indefinitely.
- The k-anonymity namespace configuration is cached to disk and served stale
  while revalidating, so a cold start with no network still answers from cache.

### Fixed - iOS

- **Background heartbeat could lose the app's background-refresh budget.** The
  `BGAppRefreshTask` expiration handler cancelled the work but relied on the
  cancelled task to call `setTaskCompleted`, which races and could complete the
  task twice or not at all. Completion is now exactly-once and reports failure
  when the window expires. The request also carries a 20 s timeout so it cannot
  outlive a refresh window.
- **The server's `heartbeat_interval_hours` was ignored**; the next refresh was
  always scheduled 24 h out. The advertised cadence is now adopted and persisted,
  so it applies from the next cold launch too.
- **`registerBackgroundHeartbeat(taskIdentifier:)` is now idempotent.**
  `BGTaskScheduler` treats a duplicate identifier as fatal, so calling it from
  both an app delegate and a SwiftUI scene (or after a state restore) crashed.
- **Metering configuration is now thread-safe.** It is written on the main thread
  at launch and read from background refresh tasks; the shared store took no lock.
- A throttled heartbeat (HTTP 429) is reported as `MeteringError.throttled` with
  the server's `Retry-After` instead of a generic bad-response error.
- An SDK below the server's minimum supported version now logs a clear upgrade
  message rather than only exposing `isDeprecated` on the result.

### Fixed - React Native / Flutter

- **Per-user tier tokens never reached the Live Caller ID Lookup extension.** The
  generated extension target had an empty entitlements file and no App Group, so
  the extension — a separate process with its own sandbox — always fell back to
  the production default and every subscriber got the default tier. The extension
  now receives the App Group in its own entitlements and Info.plist, and
  `appGroupIdentifier` resolves from the current bundle automatically.

### Server

- Monthly-active-user heartbeats are rate limited per device instead of per
  client, so a large customer's devices no longer throttle each other and get
  undercounted. Throttled responses carry `Retry-After`.

## [1.1.0]

### Changed
- **Production endpoints moved to bare subdomains**: `serviceURL` is now
  `https://pir.callerapi.com` and `tokenIssuerURL` is `https://pat.callerapi.com`
  (previously `https://api.callerapi.com/api/pir` / `/api/pat`). Apple removed
  support for path-style service / token issuer URLs in iOS/macOS 26.4; bare
  subdomains are mandatory for App Store / TestFlight builds and for the Apple
  relay onboarding form. No public API changed — rebuild against this version
  and the extension picks up the new defaults. The old path-style URLs keep
  working for Xcode dev installs and for already-deployed builds.

## [1.0.0]

Initial release.

### Added
- `CallerAPILiveCallerID` namespace: `makeExtensionContext()` for the extension
  `@main`, and host-app helpers `isDisabled(forExtensionWithIdentifier:)`,
  `openSettings()`, `refreshPIRParameters(forExtensionWithIdentifier:)`.
- `CallerAPILiveCallerIDConfiguration` with zero-config production defaults
  (`https://api.callerapi.com/api/pir` + `/api/pat`).
- App Group token sharing: `appGroupIdentifier`, `setUserTierToken(_:)`,
  `setEndpoints(serviceURL:tokenIssuerURL:)`, `resetSharedOverrides()`.
- Metering / MAU heartbeat (host app, iOS only): `configureMetering(clientKey:extensionIdentifier:endpoint:)`,
  `sendHeartbeat()`, `registerBackgroundHeartbeat(taskIdentifier:)`,
  `scheduleBackgroundHeartbeat(taskIdentifier:)`, `disableMetering()`.
- `ExtensionTemplate/` copy-in files (extension `@main`, Info.plist,
  entitlements) and a runnable `Example/` host app + extension.
- `PrivacyInfo.xcprivacy` privacy manifest (declares the App Group UserDefaults
  required-reason API + device ID for app functionality; no tracking).
- Unit tests for configuration + App Group token sharing (`swift test`).
- `sdkVersion` constant for support/diagnostics.
