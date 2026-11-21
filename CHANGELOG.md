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

## [Unreleased]

## [1.8.0] - 2026-11-20

### Changed

- **Android: the first call from a known spam number is rejected before it rings.** Up to 1.7.1 the screening service answered from memory only. The first call after an install, a force stop, a reboot, or an app update always rang. The service now looks up a number that it has not checked in the last 2 minutes, before the phone rings. The lookup sends only the bucket index, the same as before. It never sends the number. Nothing is written to disk.
- **Android: the lookup has a time limit.** It ends 3 seconds after the call arrives. A process that Android starts for the call answers within 4.5 seconds of its start. Telecom gives a screening app 5 seconds. Without an answer in time, a verdict up to 24 hours old in memory decides, or the call rings.
- **Android: saved contacts ring.** Android does not show a saved contact's call to a screening app that does not hold `READ_CONTACTS`. When your app holds that permission, the SDK now checks the contacts itself and lets the call ring. The SDK asks for no new permission.
- **Phone numbers in any format reach the right lookup.** The server keys each bucket by `+` and the digits, so a number in another format missed without an error. Up to 1.7.1, Android only put `+` in front: `8883578668` became `+8883578668`, and `0795135210` became `+0795135210`. iOS sent the number as it was. Android now reads national formats, separators, and international prefixes such as `00` and `011` in the phone's own country: the network, then the SIM, then the locale. iOS reads `+`, `00`, and North American numbers on a phone in North America. The C core now ignores separators and refuses a number without `+` with `CALLERAPI_ERR_PARSE` (-5), where it used to hash it and miss.
- **Android: a caller ID that cannot exist is rejected with no lookup.** The SDK downloads the numbering-range table that the lookup API uses: the valid number lengths of every calling code, and the allocation status of North American ranges from the NANPA and CNAC files. A number in an unallocated range, such as `+17460081173`, or with an impossible length for its country, is rejected before any lookup, also the first time it calls. The table is public numbering data, so the SDK keeps it on disk and downloads it again only when it changes. `isSpam`, `spamCheckCode`, and `cachedSpamVerdict` give spam for such a number too. A saved contact still rings. iOS cannot do this: Apple's Live Caller ID Lookup matches exact numbers only.
- **Android: one log line per screened call.** Tag `CallerAPI-Screen` shows the verdict, its source, the action, and the time, for example `verdict=SPAM source=live action=reject ms=640 number=***2730`. A number that cannot exist shows `verdict=INVALID reason=unallocated`. A failed lookup shows its error code. The result of `prewarmAsync` is logged too.
- Flutter and React Native apps get the Android changes when they upgrade the plugin to 1.8.0. On iOS, only the reading of number formats changes.

### Added

- C core: `callerapi_is_spam_live()`, the time-limited spam check that the Android screening service uses, and the error code `CALLERAPI_ERR_TIMEOUT` (-11).

## [1.7.1] - 2026-11-16

### Fixed

- **Android: `libcallerapi.so` is aligned to 16 KB.** Google Play rejects an app when a 64-bit native library does not support 16 KB memory pages. Version 1.7.0 and earlier were aligned to 4 KB on arm64-v8a and x86_64. Upgrade to 1.7.1 to pass that check. Flutter and React Native apps get the fix when they upgrade the plugin to 1.7.1. The app must also build with Android Gradle Plugin 8.5.1 or later, which packages the library with 16 KB alignment.

## [1.7.0] - 2026-11-12

### Added

- `setEntitled(bool)` on Android, iOS, Flutter, and React Native. Call it with false when a subscriber lapses. The flag is stored on the device. A later launch does not bill that device. The SDK sends one report with the feature off for the current month. Call it with true when the subscriber returns.

### Changed

- iOS 13 to 17 devices that use Call Directory now send the same usage report as iOS 18. The report uses the Call Directory switch. An upgrade to iOS 18 keeps the same device id.
- **iOS: Swift Package Manager is recommended.** The CocoaPods trunk is
  read-only, so `CallerAPI` and `CallerAPILiveCallerID` stay there at 1.6.2.
  CocoaPods still works with `:git` and `:tag` against the mirror. The React
  Native and Flutter packages now carry the iOS core and need no trunk pod.
  Remove any `pod 'CallerAPI'` line from a React Native or Flutter Podfile, and
  replace `import CallerAPI` in native host code with the wrapper module.

## [1.6.2]

The Android name card is what a customer sees on every labeled call. 1.6.1 still
drew the old bar. Upgrade if you ship call screening.

### Changed

- **Android: the caller ID overlay is a card, not a bar across the screen.** It
  was a full-width rectangle with square corners, drawn in a flat navy, with the
  name against the left edge and no vertical centring. It also set
  `FLAG_DIM_BEHIND`, which greyed out the call screen underneath it, including
  the answer and reject buttons, so a caller's name read as a modal interruption
  rather than an annotation on the call.

  It is now inset from both edges, rounded, with a real shadow, the text block
  centred against the logo, a clearer size relationship between name and number,
  and no dimming. Nothing about the lookup changed.

  This is the only place Android allows a name. Google reserves the call screen
  itself for the dialer, so a screening app draws over it, and the overlay
  either looks deliberate or it looks broken.

- **Android: a host can replace the name card.** The SDK still has no theme API.
  `setIncomingCallerIdOverlayEnabled(false)` only hides the SDK card. The
  screening service still receives every call, so the host never sees the
  number. To draw a custom card, remove `com.callerapi.sdk.CallerScreeningService`
  with `tools:node="remove"`, write your own service, answer with
  `cachedSpamVerdict`, and call `lookupLabel` after `respondToCall`. The steps
  are in `INTEGRATION.md` and `docs/public/sdk/android-call-screening.md`.

### Fixed

- **Android: the old strip no longer stacks on the new card.** The screening
  service launched `IncomingCallerIdActivity` and the overlay together. The
  activity is the fallback for devices that never granted Display over other
  apps. Launching both put the old full-width strip on top of the new card.
  The service now draws the overlay when that permission is granted, and
  launches the activity only when it is not.

## [1.6.1]

1.6.0 fixed Live Caller ID for CocoaPods and left Swift Package Manager broken,
which is the install path the documentation recommends first. Upgrade straight
past it.

### Fixed

- **The CallKit fix in 1.6.0 never reached Swift Package Manager.** The public
  package resolves from a mirror repository, and the mirror has its own
  `Package.swift`, because SwiftPM requires one at a repository root and the
  Live Caller ID sources are not one. 1.6.0 added the framework to the
  standalone manifest only, so the podspec carried the fix and the mirror did
  not, and every SwiftPM customer still had every call fail with Cocoa 4099.

  Nothing caught it. The mirror still built, because CallKit is only needed at
  run time, and the release gates check versions and slices rather than what a
  target links. `build-ios-mirror.sh` now refuses to publish a mirror that does
  not link everything the standalone package links, which fails the release
  instead of shipping it.

## [1.6.0]

Live Caller ID Lookup did not work outside an app that already happened to link
CallKit. Everything below follows from finding that, on a device, against
production.

### Fixed

- **iOS: Live Caller ID Lookup could not work at all in a host app that did not
  already link CallKit.** `LiveCallerIDLookupManager` reaches the system through
  an XPC service that lives inside
  `CallKit.framework/XPCServices/com.apple.CallKit.CallDirectory.xpc`, and an
  XPCService name resolves only against the main bundle and the frameworks
  loaded in the process. A host that linked `CallerAPILiveCallerID`, and so
  `IdentityLookup`, but never loaded CallKit failed every call before it began:

  ```
  activating connection: name=com.apple.CallKit.CallDirectory
  failed to do a bootstrap look-up: xpc_error=[3: No such process]
  invalidated after a failed init
  ```

  Everything downstream then had one symptom each and no common cause. The
  extension read as disabled however the user set the Settings toggle,
  `refreshPIRParameters` and `reset` threw Cocoa 4099, and no PIR or Privacy
  Pass request ever left the device, so the backend saw no traffic and looked
  healthy. An `import CallKit` alone autolinks only the Swift overlay, and
  weakly, so the framework is now named in `Package.swift` and the podspec.

  An app that happened to link CallKit for its own reasons was unaffected, which
  is why this survived earlier testing.

- **iOS: the SDK no longer launches the extension to find out whether it is
  enabled.** Probing readiness that way spawns an `extensionkitservice` process
  per attempt. A retry loop of them leaves `com.apple.CallKit.CallDirectory`
  holding a dead handle, and the user then cannot turn the extension off or on:
  Settings reports "an error occurred while disabling the extension" until the
  device is rebooted. Reading the status is a plain query and is now the only
  thing the readiness path does.

- **iOS: a failed `reset` no longer aborts the refresh behind it.** The first
  ExtensionKit call after an in-place app update fails with
  `com.apple.extensionKit.errorDomain` error 2, and `reset` is usually first.
  The refresh that follows it is the part the next call needs, so it now runs
  either way.

- **The server told a device its evaluation key was current when it was not.**
  `/config` reported our own receive time in `KeyStatus.timestamp`. Apple
  defines that field as the generation time of the device's secret key, and the
  key identifier is `SHA256(EvaluationKeyConfig)`, which does not change when a
  device rotates that secret. Our timestamp was always the later of the two, so
  a key derived from a superseded secret read as current, the device skipped
  `/key`, and its queries were evaluated under a key that could not decrypt
  them. The server saw nothing wrong: the config hash resolved, the key was
  found, and `/queries` answered 200 with a well formed reply. Only the device
  saw it, as a CipherML decrypt failure and an empty caller name.

### Added

- **iOS: `reset`, `refreshExtensionContext` and `reprovision`** on the public
  surface. `refreshPIRParameters` alone does not drop a cached lookup, so a
  first lookup that returned empty stayed empty for the rest of
  `cache_expiry_minutes`, which is 24 hours in production. `reprovision` runs
  Apple's working order after a package publish: optional reset, extension
  context, then PIR parameters.

- **iOS: `waitUntilEnabled`**, which polls the status until it settles. A single
  `isDisabled` read at launch is not evidence the user turned the extension off,
  because CallDirectory answers Cocoa 4099 for the first few seconds of a
  process. Host apps were treating that as "off" and hiding their own controls.

- **iOS: `isCallDirectoryUnavailable` and `isStaleExtensionConnection`**, so an
  integration can tell "the system is not ready yet, retry" apart from "the user
  has this switched off" instead of showing one misleading message for both.

- **Flutter `resetLiveLookup()` and React Native `resetLiveLookup()`**, plus an
  optional `clearCachedLookups` on the Flutter prewarm.

## [1.5.1]

Everything here comes from an external review of 1.5.0. Nothing in it changes what
the SDK can do; it changes what the SDK tells you when it is not doing it.

### Fixed

- **An SDK with no credentials now says so, instead of reporting every caller as
  clean.** `callerapi_init_ex` returned success with no credential pair, because
  nothing needs one until the first lookup. That lookup then failed
  authentication, `isSpam` reported the failure as `false`, and the result was an
  integration that started cleanly, blocked nobody, and logged nothing. A
  reviewer needed a decompiler to work out why.

  Init now fails with `CALLERAPI_ERR_NOCREDS` (-10) when neither a runtime pair
  nor a compiled-in one is available, and both platforms log what is missing and
  where to put it. A lookup that fails for any other reason, a rejected
  credential most likely, is logged once a minute rather than silently reported
  as "not spam".

  Nothing changes for an SDK that has credentials. If yours does not, it was
  already answering "not spam" to every call and now tells you.

- **iOS: the Call Directory extension no longer invents an at-rest key.** On a
  keychain miss the extension minted a fresh key, which cannot decrypt a blob the
  host encrypted, so a `keychainAccessGroup` mismatch surfaced as an empty block
  list. Only the host creates the key now; the extension reads it, and reports a
  miss.

- **iOS: `CallerAPIError` describes -9 and -10** instead of falling through to
  "unknown error".

### Documentation

- **The guide the iOS docs called canonical was never published.**
  `IOS-FULL-INTEGRATION.md` is now in the package, along with the 14 internal
  links across four documents that pointed at files customers never received.
  `build-ios-mirror.sh` repoints links renamed on the way out and refuses to
  publish a dangling one, so this cannot recur silently.

- **The iOS quickstart told you to initialise without credentials.** Its
  "complete" host `Info.plist` omitted `CallerAPISDKKey` and
  `CallerAPISDKSecret` entirely, which is what produced the silent failure above
  in the first place. Both are now in the plist example and in every launch
  snippet. The doc comment on `configure(featureEnabled:)` claimed the overload
  cannot authenticate under SwiftPM; it reads the plist, and now says so.

- **The Call Directory guide put three `Info.plist` keys on the wrong target.**
  `CallerAPIKeychainAccessGroup` is read by the extension, not the host.
  `CallerAPIAppGroup` is Live Caller ID's, and
  `CallerAPICallDirectoryExtensionBundleID` is only read by the Flutter and
  React Native bootstraps; a native app sets both in `AppConfig.swift`. There is
  a table now saying which key belongs where.

- **Android: the first call from an unknown number is not blocked, and the guide
  now says so** in its own section rather than in one KDoc comment. Screening
  answers from cache because it cannot make the phone wait, so an uncached number
  is allowed through and blocked from the second call on. Worth checking against
  any marketing copy that says otherwise.

- Android troubleshooting covers the case where every lookup returns `UNKNOWN`,
  and no longer explains lookup code -2 as a native build problem when it usually
  means the server rejected the credentials.

- The published README's install snippets are generated from `VERSION`. They had
  said 1.3.1 for three releases.

## [1.5.0]

### Added

- **Android: verified Business Caller ID.** A registered business can now prove it
  is the party placing a particular call, and only then does the incoming-call card
  show a verification mark and the business's logo.

  This is a claim about a call, not about a number, and that distinction is the
  whole feature. A spoofer presenting a customer's calling number gets the same
  answer from any number-keyed lookup as the real owner does, so the k-anon index
  now carries a business's plain name and nothing else. The mark and the logo
  travel only inside a short-lived assertion the business publishes as it dials,
  signed ES256 by the server and verified on the device against keys from
  `/api/sdk/v1/config`. There is no logo id in a bucket for any client to draw
  without checking a signature.

  The device also checks the assertion was issued for the call it is receiving, not
  merely that the business is dialling somebody, which is what stops a spoofer
  riding a real assertion by calling a different person in the same window. That
  check needs this handset's own number; where it is unavailable, verification is
  withheld. `CallerAPI.setRequireCalleeBinding(false)` relaxes it and accepts the
  weaker guarantee.

  Verification cannot block a call and does not try to. Screening runs on the main
  thread and the phone does not ring until it returns, so the assertion fetch
  happens after the verdict — it decorates a call, it never decides one.

- Logos are cached on disk by content id and fetched as a whole pack rather than
  per caller, because a request for one caller's logo would give away what the
  k-anon bucket exists to hide. Bounded to 64 MB, and every file is checked
  against its own content id before use.

- **iOS: Live Caller ID endpoints read from Info.plist.** A customer whose Apple
  registration uses a dedicated host set can set `CallerAPILCIDServiceURL` and
  `CallerAPILCIDTokenIssuerURL` instead of calling `setEndpoints`. The Swift call
  still works and still wins, so staging can override a shipped configuration.
  Only `https` URLs are accepted, and surrounding whitespace is trimmed.
- **Flutter and React Native reach the same setting through the environment.**
  The podspec hook writes both keys from `CALLERAPI_LCID_SERVICE_URL` and
  `CALLERAPI_LCID_TOKEN_ISSUER_URL`. Neither wrapper exposed `setEndpoints` in
  Dart or TypeScript, so a dedicated-host customer on Flutter or React Native
  previously needed a per-customer build of the SDK. No build differs per
  customer now.
- `bootstrap` copies a host Info.plist override into the App Group, so the
  extension reads it without a copy of its own.
- **iOS: the heartbeat installs a tier token, so Live Caller ID issuance is
  attributed to your account.** The server returns `lcid_tier_token`, the SDK
  stores it in the App Group, and the extension presents it to the Privacy Pass
  issuer. The issuer then signs with a key of your own. Nothing to call and
  nothing to configure. Billing reconciliation reads your own numbers instead of
  a fleet aggregate.

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
