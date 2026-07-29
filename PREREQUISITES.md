# Prerequisites & Apple Enrollment Checklist

**Standard CallerAPI iOS = host + Call Directory + Live Lookup.** Paid Apple Developer Program required (Call Directory uses App Groups).

RN/Flutter automated path: [`../react-native/IOS-INTEGRATION.md`](../react-native/IOS-INTEGRATION.md) Step 0.

## TL;DR checklist

- [ ] **Paid** Apple Developer Program
- [ ] Portal: App Group `group.{hostBundleId}` on host + Call Directory + Live Lookup App IDs
- [ ] iOS 18+ **physical iPhone** for call-screen LCID testing
- [ ] Xcode 16+
- [ ] LCID client key (dashboard → SDK Analytics)
- [ ] **For App Store / TestFlight:** relay enrollment (§3)

## 1. Apple Developer Program

| Goal | Account |
| --- | --- |
| **Standard integration** (Call Directory + LCID) | **Paid** ($99/yr) |
| TestFlight / App Store | **Paid** |
| Relay enrollment | **Paid** |

Call Directory cannot use App Groups on a free Personal Team — that is why the paid program is mandatory for the supported integration path.

LCID-only sample in [`Example/`](Example/README.md) is for SDK development, not the production integration path.

## 2. Extensions (ship both)

1. **Call Directory** — offline blocklist, all iOS versions ([`../ios/CALL-DIRECTORY-XCODE.md`](../ios/CALL-DIRECTORY-XCODE.md))
2. **Live Caller ID Lookup** — iOS 18+ call screen (this package)

Portal: enable **App Groups** + **Keychain Sharing** on host and Call Directory App IDs.

Live Lookup extension: **empty** `.entitlements` for local Xcode-to-device dev; add Live Caller ID Lookup capability for App Store builds.

## 3. Relay enrollment (App Store / TestFlight)

Xcode-to-device dev builds talk to the service URLs (`pir.callerapi.com` / `pat.callerapi.com`) directly. TestFlight/App Store routes through Apple's Oblivious relay — enrollment required, registered on the [Identity & Trust](https://icloud.developer.apple.com/dashboard/identity) page of the CloudKit Console under **your** Apple team with **your extension bundle id**.

Each partner gets a **dedicated set of hosts** so every Apple registration has its own service domain and its own DNS TXT proof: service URL `https://pir-<partner>.callerapi.com`, token issuer URL `https://pat-<partner>.callerapi.com`, OHTTP gateway URL `https://gateway-<partner>.callerapi.com` (e.g. `pir-eset.callerapi.com`). CallerAPI provisions these plus the gateway key-configuration resource, the validation bearer token, the Apple test identity (`+14085551212` → "Johnny Appleseed"), and the TXT record `apple-live-caller-id-lookup=<your extension bundle id>` on the service host. What you provide: the extension bundle identifier and per-continent traffic estimates. Configure the URLs in the app with `CallerAPILiveCallerID.setEndpoints(serviceURL:tokenIssuerURL:)` (or a partner build with baked defaults); the SDK's compiled-in defaults (`pir.callerapi.com` / `pat.callerapi.com`) are the shared single-tenant hosts.

Apple requires all three URLs to be **bare subdomains** (HTTPS, port 443, no path, no trailing slash) — path-style URLs were dropped in iOS/macOS 26.4. The SDK defaults comply.

[Apple docs](https://developer.apple.com/documentation/identitylookup/getting-up-to-date-calling-and-blocking-information-for-your-app)

## 4. App Group usage

| Use case | App Group required? |
| --- | --- |
| **Call Directory** blocklist storage | **Yes** — `group.{hostBundleId}` (setup script sets this) |
| **Per-user LCID tier token** (`setUserTierToken`) | Yes — same group on host + LCID extension |

Default integration works without `setUserTierToken` (single-tier token bundled).

## 5. App Store review & privacy

- SDK ships `PrivacyInfo.xcprivacy` (no tracking)
- Host app needs its own privacy manifest (RN/Flutter setup script adds Device ID `35F9.1`)
- PIR path is privacy-preserving by construction — note in review

## 6. What you cannot observe

No per-call callbacks to the host app. Validate with real incoming calls on a device.
