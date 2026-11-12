# Complete iOS integration — Native Swift

**One linear guide** for the full CallerAPI iOS stack in a native app:

- **In-app lookup** (`CallerAPI.xcframework` + `Sources/`)
- **Call Directory** (`ios/CallDirectoryExtension/` — required)
- **Live Caller ID** (`ios-lcid/` + `ios/ExtensionTemplates/LiveLookup/` — required for iOS 18+ call screen)

**Prerequisite:** Paid Apple Developer Program (Call Directory needs App Groups).

**Easier path:** React Native and Flutter use `setup_callerapi_ios.sh`. See `IOS-INTEGRATION.md` in the `@callerapi/react-native` or `callerapi` package.

---

## Step 0 — Apple Developer Portal

Before Xcode signing, register (replace `com.yourco.app`):

1. App Group: `group.com.yourco.app`
2. Host App ID: App Groups + Keychain Sharing
3. `com.yourco.app.CallDirectory`: same App Group + Keychain
4. `com.yourco.app.LiveLookup`: create identifier (empty extension entitlements for local dev)

Full checklist: Step 0 of `IOS-INTEGRATION.md` in the `@callerapi/react-native` package.

---

## What ships in your zip

```
ios/
  CallerAPI.xcframework/
  Sources/                         CallerAPI.swift, CallDirectory.swift, Entitlement.swift, DirectoryMetering.swift, Bridge.h, BackgroundSync.swift
  CallDirectoryExtension/         template (handler, Bridge.h, entitlements)
  ExtensionTemplates/LiveLookup/   LCID extension template
  CALL-DIRECTORY-XCODE.md
ios-lcid/
  Sources/CallerAPILiveCallerID/
  ExtensionTemplate/
  INTEGRATION.md                   LCID API reference
```

---

## Step 1 — Host app: C core + Swift sources

1. Drag **`ios/CallerAPI.xcframework`** → Embed & Sign
2. Add **`ios/Sources/*.swift`** + **`Bridge.h`** (bridging header)
3. Add **`libz.tbd`** (`-lz`) to host target
4. At launch:

```swift
CallerAPI.configure(featureEnabled: true)
CallerAPI.BackgroundSync.register()
```

This takes the credentials from the host `Info.plist` (Step 4). To pass them in code
instead, use `CallerAPI.configure(CallerAPIConfig(sdkKey:sdkSecret:), featureEnabled:)`.
One of the two is required.

---

## Step 2 — Call Directory extension (required)

Copy **`ios/CallDirectoryExtension/`** into your project. Create **Call Directory Extension** target.

Follow [`CALL-DIRECTORY-XCODE.md`](CALL-DIRECTORY-XCODE.md):

- Link xcframework + `CallDirectory.swift` + `CallerAPI.swift` + `Entitlement.swift` to extension
- `Bridge.h`, `CALLERAPI_BRIDGING_ONLY`, `-lz`
- Embed in host **PlugIns**
- Host + extension entitlements (App Group + Keychain)
- Host plist keys + `INFOPLIST_PREPROCESS = YES`

```swift
CallerAPI.CallDirectory.configure(.init(
    appGroup: "group.com.yourco.app",
    extensionBundleID: "com.yourco.app.CallDirectory",
    keychainAccessGroup: "$(AppIdentifierPrefix)com.yourco.app.shared"))
CallerAPI.CallDirectory.scheduleDeferredSync(after: 60)
```

---

## Step 3 — Live Lookup extension (required)

Copy **`ios/ExtensionTemplates/LiveLookup/`** (or `ios-lcid/ExtensionTemplate/`). Create **Live Caller ID Lookup Extension** target.

```swift
import IdentityLookup
import CallerAPILiveCallerID

@main
struct LiveLookupExtension: LiveCallerIDLookupProtocol {
    var context: LiveCallerIDLookupExtensionContext {
        CallerAPILiveCallerID.makeExtensionContext()
    }
}
```

- Extension Info.plist: `com.apple.live-lookup`, `CFBundleExecutable`, `XPC!`
- **Empty** extension entitlements for local dev signing
- Add LCID sources to extension (not `Metering.swift`)
- Embed in host **Extensions** folder
- Host plist: `CallerAPILiveLookupExtensionBundleID`, `CallerAPILCIDClientKey`, heartbeat task id

```swift
CallerAPILiveCallerID.bootstrap(.init(
    extensionIdentifier: "com.yourco.app.LiveLookup",
    lcidClientKey: "YOUR_LCID_CLIENT_KEY",
    heartbeatTaskIdentifier: "com.yourco.app.lcid.heartbeat",
    appGroupIdentifier: "group.com.yourco.app"))
```

See [`../ios-lcid/INTEGRATION.md`](LIVE-CALLER-ID.md) for LCID API details.

---

## Step 4 — Host Info.plist (complete)

```xml
<key>CallerAPISDKKey</key><string>YOUR_SDK_KEY</string>
<key>CallerAPISDKSecret</key><string>YOUR_SDK_SECRET</string>
<key>CallerAPILiveLookupExtensionBundleID</key><string>com.yourco.app.LiveLookup</string>
<key>CallerAPILCIDClientKey</key><string>YOUR_LCID_CLIENT_KEY</string>
<key>CallerAPILCIDHeartbeatTaskID</key><string>com.yourco.app.lcid.heartbeat</string>
<key>CallerAPIAppGroup</key><string>group.com.yourco.app</string>
<key>CallerAPICallDirectoryExtensionBundleID</key><string>com.yourco.app.CallDirectory</string>
<key>CallerAPIKeychainAccessGroup</key><string>$(AppIdentifierPrefix)com.yourco.app.shared</string>
<key>UIBackgroundModes</key><array><string>fetch</string></array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.callerapi.checkin</string>
  <string>com.yourco.app.lcid.heartbeat</string>
</array>
```

`CallerAPISDKKey` and `CallerAPISDKSecret` are what make lookups work. Without them
init fails, every lookup reports "not spam", and nothing is blocked. The SDK logs the
reason under subsystem `com.callerapi.sdk`; pass them to `configure` in code instead
if you would rather not keep them in the plist.

Also add `CallerAPIKeychainAccessGroup` to the **Call Directory extension's** plist.
The extension reads it from its own bundle, and a mismatch between the two is the usual
cause of a sync that succeeds and a block list that stays empty.

**Info.plist Preprocessor = YES** on host and Call Directory extension.

---

## Step 5 — Dashboard client key

Dashboard → SDK Analytics → New app → iOS → bundle id = host app → copy `client_key`.

---

## Step 6 — Enable on device

**Settings → Phone → Call Blocking & Identification**

1. Enable **Call Directory** → host calls `CallDirectory.sync()` or deferred sync runs
2. Enable **Live Lookup** (iOS 18+)
3. Test call from another phone

---

## React Native / Flutter

Use `setup_callerapi_ios.sh` in the platform package — automates Steps 2–4:

- `IOS-INTEGRATION.md` in the `@callerapi/react-native` package (npm)
- `IOS-INTEGRATION.md` in the `callerapi` package (pub.dev)
