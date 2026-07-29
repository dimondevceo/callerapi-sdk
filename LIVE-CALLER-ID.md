# CallerAPI — Live Caller ID Lookup (iOS 18+) Integration

**Part of the full iOS stack** — ship alongside **Call Directory** (required).
Native linear guide: [`../ios/IOS-FULL-INTEGRATION.md`](../ios/IOS-FULL-INTEGRATION.md).

**Paid Apple Developer Program required** for the standard CallerAPI iOS stack (Call Directory uses App Groups). RN/Flutter automated path:

- [`../react-native/IOS-INTEGRATION.md`](../react-native/IOS-INTEGRATION.md)
- [`../flutter/IOS-INTEGRATION.md`](../flutter/IOS-INTEGRATION.md)

This package adds **Live Caller ID Lookup**: privacy-preserving, real-time caller
ID and spam blocking on the incoming-call screen, backed by CallerAPI PIR at
`api.callerapi.com`.

> **Stuck on signing or entitlements?** Compare your files to
> `ios/ExtensionTemplates/LiveLookup/` in your zip (empty entitlements for free-team dev).

---

## TL;DR checklist (do these in order)

- [ ] iPhone on **iOS 18+** (real device for call-screen testing)
- [ ] Xcode **16+**
- [ ] Add `CallerAPILiveCallerID` package (Step 1)
- [ ] Create **Live Caller ID Lookup Extension** target (Step 2)
- [ ] Extension bundle id **nested** under host, e.g. `com.yourco.app.LiveLookup`
- [ ] Extension **embedded** in host app; built by your scheme
- [ ] Extension Info.plist: `EXExtensionPointIdentifier = com.apple.live-lookup`
  + `CFBundleExecutable = $(EXECUTABLE_NAME)`
- [ ] Extension entitlements **empty** `<dict/>` for local Xcode-to-device dev signing
- [ ] Host app: `CallerAPILiveCallerID.bootstrap(...)` once at launch (Step 3)
- [ ] LCID **client key** from dashboard → SDK Analytics (Step 7)
- [ ] Host Info.plist: `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes`
- [ ] User enables extension in **Settings → Phone → Call Blocking & Identification**
- [ ] Verify with a test call (see **Verify it worked** below)

---

## What this actually is (read this first)

Live Caller ID Lookup is an **iOS 18 system feature**. When a call comes in, the
**operating system itself** — not your app — privately queries the CallerAPI
backend and shows the result on the call screen. The query is protected by three
Apple technologies the OS runs for you:

- **Oblivious HTTP** — hides the device IP from our servers.
- **Privacy Pass** — anonymous, single-use auth tokens (our issuer at
  `pat.callerapi.com`).
- **Keyword PIR** (homomorphic encryption) — the server answers the query
  *without learning which number was looked up* (our PIR origin at
  `pir.callerapi.com`).

Your app's only job is to ship a small **app extension** that tells the system
two URLs and a token. **There is no PIR, crypto, or networking code in the
extension** — the SDK is intentionally tiny because the OS does everything.

```
Incoming call ─▶ iOS system ──Privacy Pass + OHTTP + PIR──▶ pir/pat.callerapi.com
                     │
                     └─ reads serviceURL + tokenIssuerURL + userTierToken
                        from YOUR extension (once, at enable time)
```

> **Apple relay enrollment** is required for TestFlight/App Store. Xcode-to-device
> dev builds talk to the service URLs directly. Apple requires the service and
> issuer URLs to be **bare subdomains** (no paths) since iOS 26.4 — the SDK
> defaults comply. See [`PREREQUISITES.md`](PREREQUISITES.md).

---

## Requirements

- iOS 18.0+ (the feature does not exist before iOS 18)
- Xcode 16+
- **Paid Apple Developer Program** for the full CallerAPI iOS stack (Call Directory + LCID shipping together)
- LCID-only local dev on a free Personal Team is possible in isolation, but **not** the supported integration path — see [`../react-native/IOS-INTEGRATION.md`](../react-native/IOS-INTEGRATION.md)

---

## Step 1 — Add the package

In your CallerAPI release zip, this package lives at **`ios-lcid/`**. Reference it as a **local** Swift package:

```swift
// Package.swift dependency
.package(path: "../ios-lcid")
```

Or in Xcode: **File → Add Package Dependencies → Add Local…** → select the `ios-lcid` folder from your zip.

---

## Step 2 — Create the extension target

In Xcode: **File ▸ New ▸ Target… ▸ Live Caller ID Lookup Extension**, name it
e.g. `LiveLookup`. Xcode generates a stub — replace it with the template in
`ExtensionTemplate/`:

1. Replace the generated Swift file with
   `ExtensionTemplate/CallerAPILiveLookupExtension.swift`.
2. Merge `ExtensionTemplate/Info.plist` — critical keys:
   ```xml
   <key>CFBundleExecutable</key>
   <string>$(EXECUTABLE_NAME)</string>
   <key>CFBundlePackageType</key>
   <string>XPC!</string>
   <key>EXAppExtensionAttributes</key>
   <dict>
       <key>EXExtensionPointIdentifier</key>
       <string>com.apple.live-lookup</string>
   </dict>
   ```
3. Add the `CallerAPILiveCallerID` library to the **extension target's**
   "Frameworks and Libraries".

That's the whole extension:

```swift
import IdentityLookup
import CallerAPILiveCallerID

@main
struct CallerAPILiveLookupExtension: LiveCallerIDLookupProtocol {
    var context: LiveCallerIDLookupExtensionContext {
        CallerAPILiveCallerID.makeExtensionContext()
    }
}
```

> **The four things that actually block the extension from installing/enabling**
> (templates in `ios/ExtensionTemplates/LiveLookup/`):
>
> 1. **Bundle id must be nested under the host app**, e.g.
>    `com.yourco.app.LiveLookup`. If it isn't a child of the host id, the
>    toggle never appears in Settings.
> 2. **The extension must be embedded** in the host app and built by your scheme.
> 3. **Info.plist must be complete.** Besides `EXAppExtensionAttributes`, an
>    ExtensionKit bundle needs `CFBundleExecutable = $(EXECUTABLE_NAME)` and
>    `CFBundlePackageType = XPC!`. Missing `CFBundleExecutable` fails install with
>    *"has missing or invalid CFBundleExecutable in its Info.plist"*.
> 4. **Local dev signing:** leave the extension's `.entitlements` an empty
>    `<dict/>`. Do **not** add
>    `com.apple.developer.identitylookup.live-caller-id-lookup` until a paid-account
>    App Store build — otherwise signing fails with `amfid … -413`.

By default it points at production:

| Parameter        | Value                                    |
| ---------------- | ---------------------------------------- |
| `serviceURL`     | `https://pir.callerapi.com`              |
| `tokenIssuerURL` | `https://pat.callerapi.com`              |
| `userTierToken`  | bundled single-tier default (see Step 5) |

(Bare subdomains are an Apple requirement since iOS 26.4 — path-style URLs are
rejected for App Store builds.)

---

## Step 3 — Bootstrap the host app (recommended — out of the box)

Call **once** from `application(_:didFinishLaunchingWithOptions:)`. This wires
metering, background heartbeat, and **automatic LCID prewarm** (at launch and
every time the app returns to foreground) so the first incoming call is not
racing a cold Privacy Pass / PIR path:

```swift
import CallerAPILiveCallerID

let extID = "com.yourco.app.LiveLookup"   // extension bundle id

CallerAPILiveCallerID.bootstrap(.init(
    extensionIdentifier: extID,
    lcidClientKey: "YOUR_LCID_CLIENT_KEY",              // dashboard → SDK Analytics
    heartbeatTaskIdentifier: "com.yourco.app.lcid.heartbeat"  // Info.plist BGTask id
))
```

Add the heartbeat task id to the host app Info.plist (see Step 7). You do **not**
need to call `refreshPIRParameters` manually on launch — bootstrap does it.

> **React Native / Flutter:** see [`../react-native/IOS-INTEGRATION.md`](../react-native/IOS-INTEGRATION.md) — automated plist + bootstrap.

---

## Step 4 — Prompt the user to enable it (host app)

The extension is **disabled until the user turns it on** in
**Settings → Phone → Call Blocking & Identification** (some iOS versions:
**Settings → Apps → Phone → …**). From your app:

```swift
import CallerAPILiveCallerID

let extID = "com.yourco.app.LiveLookup"

if CallerAPILiveCallerID.isDisabled(forExtensionWithIdentifier: extID) {
    try await CallerAPILiveCallerID.openSettings()
}
```

---

## Step 5 — (Optional) per-user token via App Group

The CallerAPI Privacy Pass issuer is currently **single-tier**: it presence-checks
the `userTierToken` and accepts the bundled default, so Steps 1–4 work as-is. To
attach a real per-user token (recommended once you authenticate users):

1. Add an **App Group** capability to **both** the app and the extension targets
   with the same identifier (e.g. `group.com.yourco.app`).
2. In the **extension** `init()`, set the identifier:
   ```swift
   CallerAPILiveCallerID.appGroupIdentifier = "group.com.yourco.app"
   ```
3. In the **host app**, set the same identifier and push the token after login:
   ```swift
   CallerAPILiveCallerID.appGroupIdentifier = "group.com.yourco.app"
   CallerAPILiveCallerID.setUserTierToken(myUserToken)
   try await CallerAPILiveCallerID.refreshPIRParameters(forExtensionWithIdentifier: extID)
   ```

---

## Step 6 — Refresh on server changes

The system periodically refreshes parameters on its own. To force it (e.g. after
a push telling you the dataset/config changed, or after changing the token):

```swift
try await CallerAPILiveCallerID.refreshPIRParameters(forExtensionWithIdentifier: extID)
```

For lower-level controls (`reset(forExtensionWithIdentifier:)`,
`refreshExtensionContext(forExtensionWithIdentifier:)`), use
`CallerAPILiveCallerID.manager` (the shared `LiveCallerIDLookupManager`).

---

## Step 7 — (Required for billing) device metering

Billing is **per active device** (devices that have the extension enabled). Step 3
`bootstrap(_:)` already calls `configureMetering`, sends an initial heartbeat,
and registers the background heartbeat task when you pass `heartbeatTaskIdentifier`.

> **Not optional if you want billing.** Without a client key the device is never
> counted and the **SDK Analytics dashboard stays at zero**.

**Provision a client key:** CallerAPI dashboard → **SDK Analytics → New app**,
platform **iOS**, **host app bundle id**. Pass the returned key as `lcidClientKey`
in `bootstrap(_:)` (the `X-LCID-Client-Key` header — **not** your dashboard API key).

Two Info.plist additions in the **host app** for the background task:

```xml
<key>UIBackgroundModes</key>
<array><string>fetch</string></array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array><string>com.yourco.app.lcid.heartbeat</string></array>
```

`sendHeartbeat()` also returns the server's version policy
(`latestVersion`, `minSupportedVersion`, `isDeprecated`) so you can nudge users to
update. To opt a device out entirely, call `CallerAPILiveCallerID.disableMetering()`.

---

## Verify it worked

1. Build to a **physical iPhone** on iOS 18+ (not Simulator for call-screen labels).
2. Enable the extension in **Settings → Phone → Call Blocking & Identification**
   (same menu path as Call Directory — enable the **Live Lookup** row).
3. Launch the app once — Xcode console should show
   `[CallerAPI][LCID] prewarm(bootstrap) ok`.
4. Place a **test call from another phone** — expect a caller label or spam treatment.
5. Dashboard → **SDK Analytics** → Active devices should be ≥ 1 after launch.

If the extension code changed but behavior didn't: **delete the app** from the
device and reinstall.

---

## How CallerAPI serves the two use cases

The OS issues **two** requests per incoming call (always both, to avoid leaking
whether a number was seen before):

| Usecase              | Server data                                   | Result on screen       |
| -------------------- | --------------------------------------------- | ---------------------- |
| `callerapi.block`    | 1 byte (`0x01` = spam) + live freshness stash | Silenced / spam label  |
| `callerapi.identity` | serialized `CallIdentity` (name, category…)   | Business / caller name |

You don't configure these in the app — the system discovers them from the PIR
origin's `/config` endpoint. They're produced and kept fresh by the CallerAPI
backend.

---

## Relationship to the rest of the CallerAPI SDK

Ship **all three** on iOS: host lookups (`ios/Sources/`), **Call Directory** (`ios/CallDirectoryExtension/`), and this LCID package. Linear native guide: [`../ios/IOS-FULL-INTEGRATION.md`](../ios/IOS-FULL-INTEGRATION.md).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `amfid … -413 "No matching profile found"` | LCID entitlement on wrong team/profile | Empty extension `.entitlements` for local dev (Step 2) |
| Install fails: *"has missing or invalid CFBundleExecutable"* | Incomplete extension Info.plist | Add `CFBundleExecutable`, `CFBundlePackageType = XPC!` (Step 2) |
| LCID toggle never appears in Settings | iOS < 18, extension not embedded, or bundle id not nested | iOS 18 device; embed extension; nest bundle id (Step 2) |
| Build error `Missing package product 'CallerAPILiveCallerID'` | Stale SPM resolution | Re-resolve packages; clear DerivedData; or copy `ios-lcid/Sources/` directly into your target |
| Dashboard SDK Analytics stays at **0** | No client key or heartbeat not wired | Provision key (Step 7); confirm `bootstrap` runs on launch |
| Heartbeat `401 unknown_client` / `403 bundle_mismatch` | Wrong key or client bundle id ≠ app | Re-copy key; dashboard bundle id = host app exactly (Step 7) |
| Requests go to `http://www.example.com/config` | Extension isn't providing context | `@main` + `LiveCallerIDLookupProtocol`; `com.apple.live-lookup` (Step 2) |
| `failed to fetch token key` / `server error` | Relay can't reach issuer | Confirm relay enrollment; `tokenIssuerURL` = `https://pat.callerapi.com` |
| Extension never fires on a call | Disabled in Settings, or not iOS 18 | `isDisabled` + `openSettings()`; real device + real call |
| An extension "won't update" after a code change | iOS caches embedded extensions | Delete the app from the device and reinstall |
