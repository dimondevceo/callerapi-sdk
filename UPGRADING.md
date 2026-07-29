# Upgrading the CallerAPI SDK

Every platform ships through its ecosystem's normal public package registry, so
upgrading is a version bump in your own manifest. There is no archive to
download, no vendored copy to replace, no registry credentials to configure, and
no CallerAPI-specific tooling.

All platforms share one version number (see `VERSION`), so `1.3.0` on Android and
`1.3.0` on iOS are the same release.

Downloading a package does not grant a licence to use it: the SDK authenticates
to the CallerAPI service with the credentials issued under your subscription. See
`LICENSE`.

## Upgrading to 1.4.0 from 1.3.x: iOS needs your credentials

Android reads its credentials from manifest `meta-data`, and always has. iOS had no
equivalent, so lookups through the published pod could not authenticate at all. They
failed with `CallerAPIError` code `-2`.

1.4.0 adds the missing path. Do one of the two, once, before your first lookup.

In code:

```swift
import CallerAPI

CallerAPI.configure(CallerAPIConfig(
    sdkKey: "<from the dashboard>",
    sdkSecret: "<from the dashboard>"
))
```

Or in your app's Info.plist, which is also where the Flutter and React Native bridges
read them from:

```xml
<key>CallerAPISDKKey</key>
<string>...</string>
<key>CallerAPISDKSecret</key>
<string>...</string>
```

Nothing else changed. The existing `configure(featureEnabled:)` still compiles, and
still works on a per-customer build with credentials compiled in.

## Android

```kotlin
dependencies {
    implementation("com.callerapi:callerapi-sdk:1.3.0")
}
```

Published to Maven Central, so `mavenCentral()` in your repositories is all that
is required — no credentials and no custom repository. If your organisation
proxies dependencies through Artifactory or Nexus, the coordinates resolve there
as soon as your mirror has synced Central.

## iOS — Swift Package Manager

```swift
dependencies: [
    .package(
        url: "https://github.com/dimondevceo/callerapi-sdk.git",
        from: "1.3.0"
    ),
]
```

Or in Xcode: **File ▸ Add Package Dependencies…**, then *Up to Next Major
Version*. Upgrading later is **File ▸ Packages ▸ Update to Latest Package
Versions**.

The package offers two products and most apps take both:

```swift
.target(name: "YourApp", dependencies: [
    .product(name: "CallerAPI", package: "callerapi-sdk"),
    .product(name: "CallerAPILiveCallerID", package: "callerapi-sdk"),
]),
```

`CallerAPI` is spam detection, caller labels, and the Call Directory blocklist, and
works from iOS 13. `CallerAPILiveCallerID` is Apple's system-level Live Caller ID
Lookup and needs iOS 18. They are additive — neither replaces the other.

## iOS — CocoaPods

```ruby
pod 'CallerAPI', '~> 1.3'
pod 'CallerAPILiveCallerID', '~> 1.3'   # iOS 18+ Live Caller ID Lookup
```

Then `pod update CallerAPI CallerAPILiveCallerID`.

## React Native

```bash
npm install @callerapi/react-native@1.3.0 && cd ios && pod install
```

## Flutter

```yaml
dependencies:
  callerapi: ^1.3.0
```

Then `flutter pub upgrade callerapi`.

Both wrappers pull the native SDKs in themselves — Maven Central on Android and the
`CallerAPI` pod on iOS — so there is nothing else to add. If you are coming from
1.3.0 or earlier and your project has a `CallerAPI` folder or a `jniLibs` directory
that a setup script once copied in, delete it: it is now resolved as a dependency,
and a leftover copy is an older core competing with the current one.

---

## Credentials are runtime configuration

Earlier builds baked your SDK key and secret into the native binary, which is why
each customer received a bespoke archive. They are now supplied at runtime, so the
package you install is identical to every other customer's and can be upgraded
independently of your credentials.

**Android** — in code:

```kotlin
CallerAPI.register(
    context = this,
    config = CallerAPIConfig(
        clientKey = BuildConfig.CALLERAPI_CLIENT_KEY,
        sdkKey = BuildConfig.CALLERAPI_SDK_KEY,
        sdkSecret = BuildConfig.CALLERAPI_SDK_SECRET,
    ),
)
```

…or with no SDK-specific code at all, via the manifest (values can come from your
own Gradle properties, so secrets stay out of source control):

```xml
<application>
    <meta-data android:name="com.callerapi.sdk.CLIENT_KEY" android:value="${callerApiClientKey}" />
    <meta-data android:name="com.callerapi.sdk.SDK_KEY"    android:value="${callerApiSdkKey}" />
    <meta-data android:name="com.callerapi.sdk.SDK_SECRET" android:value="${callerApiSdkSecret}" />
</application>
```

The manifest route also covers the case where Android starts your process to
deliver an incoming call before your `Application.onCreate` has configured the SDK
in code.

**iOS** — `CallerAPILiveCallerID.bootstrap(_:)` already takes the client key as a
parameter; nothing changes.

> **A note on secrecy.** A key shipped inside an app binary is recoverable by
> anyone who can run that app, on every platform. Treat `sdkKey`/`sdkSecret` as
> identifying, not authenticating: the server rate-limits and meters per device,
> and abuse is detected server-side. Never reuse these values for anything that
> guards data outside the SDK.

## Device attestation (optional, recommended)

Because your credentials ship inside your app, possession of them proves nothing on
its own. From 1.3.0 the SDK can prove instead that a request came from a genuine,
unmodified build of *your* app on a genuine device — something an attacker holding
your extracted key cannot produce.

This is off until CallerAPI enables it for your account, and enabling it is a
conversation rather than a switch: it starts in a monitoring mode that records what
enforcement *would* have rejected, so you can see the effect on your own fleet
before anything is refused.

**Android** — add the Play Integrity dependency. It is not a transitive dependency
of ours because it needs the Google Cloud project attached to your own Play Console
listing:

```kotlin
dependencies {
    implementation("com.google.android.play:integrity:1.4.0")
}
```

You will also need to grant CallerAPI a service account that can decode your
integrity tokens — Google encrypts them to your cloud project, so we cannot read
them otherwise. Ask support for the current instructions.

Without the dependency the SDK still works; it simply reports no attestation.

**iOS** — nothing to add. App Attest is part of the OS and the SDK uses it
automatically once your account has it enabled. It does not work on the simulator,
so test on a real device.

**Both** — the SDK also now reports your app's identity on every authentication:
the bundle identifier on iOS, and the `applicationId` plus signing-certificate
SHA-256 on Android, read from the OS rather than from configuration. If you use
Play App Signing, the digest CallerAPI needs is the one Play shows under **App
signing key certificate**, not your upload key.

### If a device is refused

The SDK logs the reason and what to do about it. The reasons you are most likely to
see while setting this up:

| Reason | Meaning |
|---|---|
| `package_mismatch` / `cert_mismatch` / `bundle_mismatch` | Your credential is provisioned for a different app. Usually a re-signed build or an upload-key digest where the Play signing digest was needed. |
| `attestation_required` | Attestation is required and this build sent none — on Android, the Play Integrity dependency is missing. |
| `integrity_device_*` | Play Integrity judged the device or build untrustworthy: an emulator, a rooted device, or a sideloaded APK. |
| `attestation_development_build` | A development-profile iOS build. Use TestFlight or App Store. |
| `mau_cap_reached` | Your plan's monthly active device ceiling. Contact CallerAPI. |

## Version policy and upgrade prompts

Each heartbeat returns `latest_sdk_version`, `min_supported_sdk_version` and
`sdk_deprecated`. Surface it so users on an unsupported build get updated:

- **Android** — the SDK logs a warning; `Metering` also exposes the values if you
  want to drive your own UI.
- **iOS** — `try await CallerAPILiveCallerID.sendHeartbeat()` returns a
  `HeartbeatResult` with `isDeprecated` and `latestVersion`.

## 1.2.0 → 1.3.0

Source-compatible; no code changes are required. Everything new is opt-in per
account and defaults to off, so an existing integration behaves exactly as it did.

Two things worth knowing:

1. **Your app's identity is now reported on every authentication.** Nothing to do,
   but if your account already has identity pinning configured for a *different*
   package name or signing certificate, requests will be refused — see the table
   above. Check with support before upgrading if you have re-signed your app.
2. **`app_version` now reports the real SDK version.** It was previously hardcoded
   to `1.0.0`, so CallerAPI's version policy could not tell an outdated integration
   from a current one. Deprecation warnings will start being accurate.

## 1.1.x → 1.2.0

Source-compatible. Two behaviour changes worth knowing:

1. **Android call screening no longer performs network I/O.** `onScreenCall` now
   answers from the local cache and responds immediately, then warms the cache in
   the background. A first-ever caller is allowed through rather than delaying the
   ring; a repeat caller is screened. If you called `CallerAPI.isSpam` from your
   own screening code, switch to `CallerAPI.cachedSpamVerdict` — it returns
   `SPAM`, `CLEAN` or `UNKNOWN` and never blocks.
2. **Consented block counts are reported on exactly one channel.** If you were
   reconciling numbers against the dashboard, previous versions could double-count
   blocks; the totals reported from 1.2.0 are lower and correct.
