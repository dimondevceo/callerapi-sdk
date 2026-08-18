# CallerAPI for iOS

Caller identification and spam detection that does not tell us who is calling you.

Two products ship from this package. Most apps take both.

| Product | What it does | Requires |
| --- | --- | --- |
| `CallerAPI` | Spam detection, caller labels, and the CallKit Call Directory blocklist | iOS 13+ |
| `CallerAPILiveCallerID` | Apple's system-level Live Caller ID Lookup, which identifies callers before you answer | iOS 18+ |

They are additive. `CallerAPI` gives you lookups your app controls and blocking on
older devices; `CallerAPILiveCallerID` hands iOS 18 the details it needs to do the
lookup itself, on every incoming call, without your app running.

## Install

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** → `https://github.com/dimondevceo/callerapi-sdk`

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/dimondevceo/callerapi-sdk", from: "1.6.1"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "CallerAPI", package: "callerapi-sdk"),
        .product(name: "CallerAPILiveCallerID", package: "callerapi-sdk"),
    ]),
]
```

### CocoaPods

```ruby
pod 'CallerAPI', '~> 1.6.1'
pod 'CallerAPILiveCallerID', '~> 1.6.1'   # iOS 18+ Live Caller ID Lookup
```

### React Native and Flutter

Don't add anything here — both wrappers depend on these pods already:

```sh
npm install @callerapi/react-native     # React Native
flutter pub add callerapi               # Flutter
```

## Credentials

You need an SDK key and secret. Create an app at
[callerapi.com/dashboard/sdk-setup](https://callerapi.com/dashboard/sdk-setup) and
it will show you both, along with a snippet for your platform with the values
already filled in.

New apps start in sandbox, capped at 200 devices — enough to develop and test
against, not enough to launch on. Lifting the cap is a conversation about pricing;
email support@callerapi.com when you're ready.

## Guides

- [IOS-FULL-INTEGRATION.md](IOS-FULL-INTEGRATION.md) — start here: host app, Call Directory, and Live Caller ID wired in order
- [CORE-INTEGRATION.md](CORE-INTEGRATION.md) — setting up `CallerAPI`
- [CALL-DIRECTORY-XCODE.md](CALL-DIRECTORY-XCODE.md) — the blocklist extension for iOS 13–17
- [PREREQUISITES.md](PREREQUISITES.md) — what Apple needs to grant you before Live Caller ID works
- [LIVE-CALLER-ID.md](LIVE-CALLER-ID.md) — setting up `CallerAPILiveCallerID`
- [UPGRADING.md](UPGRADING.md) — version-to-version changes
- [CHANGELOG.md](CHANGELOG.md)

Apple requires an entitlement for Live Caller ID Lookup and reviews the request.
Start [PREREQUISITES.md](PREREQUISITES.md) early — it is the long pole, and nothing
about that extension works until it is granted.

## Support

- Issues: https://github.com/dimondevceo/callerapi-sdk/issues
- Commercial and licensing: support@callerapi.com

---

This repository is generated. It is published automatically from CallerAPI's
internal monorepo on every release, so pull requests here cannot be merged —
please open an issue instead.
