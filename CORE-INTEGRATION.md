# CallerAPI iOS SDK — Integration

> **Full stack (recommended):** [`IOS-FULL-INTEGRATION.md`](IOS-FULL-INTEGRATION.md) — lookup + **Call Directory** + **Live Caller ID**. All three are required for a production CallerAPI iOS app.

This file covers the **host app lookup API**. Call Directory and LCID are **not optional** — see the full guide above.

---

## What you received

```
ios/
  CallerAPI.xcframework/
  Sources/                    CallerAPI.swift, CallDirectory.swift, Entitlement.swift, DirectoryMetering.swift, Bridge.h, BackgroundSync.swift
  CallDirectoryExtension/     required Call Directory template
  ExtensionTemplates/LiveLookup/
  CALL-DIRECTORY-XCODE.md
  IOS-FULL-INTEGRATION.md     start here for complete wiring
```

**Prerequisite:** Paid Apple Developer Program (Call Directory needs App Groups).

---

## Step 1 — Add the framework

Drag **`CallerAPI.xcframework`** → **Embed & Sign**. Add **`libz.tbd`** (`-lz`).

## Step 2 — Add Swift sources

Drag **`Sources/`** into your project. Set **Objective-C Bridging Header** to `Bridge.h`.

Include **`CallDirectory.swift`** — required for the Call Directory extension path.

## Step 3 — Initialize at launch

Pass the credentials from your dashboard. The published package carries none, so
a lookup made without them fails with code `-2`:

```swift
CallerAPI.configure(
    CallerAPIConfig(sdkKey: "<your key>", sdkSecret: "<your secret>"),
    featureEnabled: true)
CallerAPI.BackgroundSync.register()
```

You can put the pair in the host `Info.plist` as `CallerAPISDKKey` and
`CallerAPISDKSecret` instead, which is what makes lookups work through Flutter and
React Native. `configure(featureEnabled:)` with no config is for per-customer builds
that have credentials compiled in; on SwiftPM or CocoaPods it cannot authenticate.

## Step 4 — Lookups

```swift
let isSpam = try await CallerAPI.isSpam("+14155551234")
let label  = try await CallerAPI.lookupLabel("+14155551234")
```

Pass the number with `+` and the country code. `00` and North American formats also
work. A national number outside North America needs its country code.

## Step 5 — Call Directory (required)

Follow [`CALL-DIRECTORY-XCODE.md`](CALL-DIRECTORY-XCODE.md) or [`IOS-FULL-INTEGRATION.md`](IOS-FULL-INTEGRATION.md).

```swift
CallerAPI.CallDirectory.configure(.init(
    appGroup: "group.com.yourco.app",
    extensionBundleID: "com.yourco.app.CallDirectory",
    keychainAccessGroup: "$(AppIdentifierPrefix)com.yourco.app.shared"))
CallerAPI.CallDirectory.scheduleDeferredSync(after: 60)
```

Enable in **Settings → Phone → Call Blocking & Identification**, then sync.

## Step 6 — Live Caller ID (required, iOS 18+)

[`../ios-lcid/INTEGRATION.md`](LIVE-CALLER-ID.md) — Live Lookup extension + bootstrap + client key.

## Step 7 — Info.plist

See [`IOS-FULL-INTEGRATION.md`](IOS-FULL-INTEGRATION.md#step-4--host-infoplist-complete). Set **Info.plist Preprocessor = YES** on host and Call Directory extension.

## React Native / Flutter

Automated by `setup_callerapi_ios.sh`. The guide ships inside each wrapper package as
`IOS-INTEGRATION.md`: `@callerapi/react-native` on npm, `callerapi` on pub.dev.

---

## Troubleshooting

| Issue | Fix |
| --- | --- |
| `Undefined symbol: _inflate` | Add `libz.tbd` |
| `Undefined symbol: _callerapi_*` | Embed xcframework + bridging header |
| Call Directory empty | Enable toggle; sync; matching App Group + Keychain |
| No call-screen ID | iOS 18+; enable Live Lookup; client key in plist |
