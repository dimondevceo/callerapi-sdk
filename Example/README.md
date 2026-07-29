# CallerAPIDemo - runnable Live Caller ID Lookup example

> **Production CallerAPI iOS** ships Call Directory + LCID together (paid Apple account).
> This sample is **LCID-only** for SDK development. Full stack: [`../../ios/IOS-FULL-INTEGRATION.md`](../../ios/IOS-FULL-INTEGRATION.md) or RN/Flutter [`../../react-native/IOS-INTEGRATION.md`](../../react-native/IOS-INTEGRATION.md).

A minimal host app + Live Caller ID Lookup extension that integrates the
`CallerAPILiveCallerID` SDK (one directory up) and points at the production
CallerAPI backend (`https://pir.callerapi.com` + `https://pat.callerapi.com`).

This was built and **compiled clean for the iOS 18 Simulator** (Xcode 16.1).
The extension embeds correctly at `CallerAPIDemo.app/Extensions/LiveLookupExtension.appex`.

```
Example/
├── project.yml                       # XcodeGen spec (host app + extension targets)
├── CallerAPIDemo/                     # SwiftUI host app
│   ├── CallerAPIDemoApp.swift
│   └── ContentView.swift             # status + "Open Settings" + "Refresh PIR params"
└── LookupExtension/                   # the Live Caller ID Lookup extension
    ├── LiveLookupExtension.swift     # 8-line @main LiveCallerIDLookupProtocol
    └── Info.plist                    # EXExtensionPointIdentifier = com.apple.live-lookup
```

## Open the project

The generated `CallerAPIDemo.xcodeproj` is gitignored. Regenerate it with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen          # once
cd sdk/ios-lcid/Example
xcodegen generate
open CallerAPIDemo.xcodeproj
```

(If you prefer not to use XcodeGen, the same two targets can be created by hand
in Xcode - see the parent `../INTEGRATION.md`. XcodeGen just removes the manual
clicking and guarantees the ExtensionKit product type + embedding are correct.)

## Run on the iOS Simulator (free, no Apple Developer account)

```bash
xcodebuild -project CallerAPIDemo.xcodeproj -scheme CallerAPIDemo \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

…or just hit ▶ in Xcode with an iPhone 16 / iOS 18 simulator selected.

The host app launches and shows the extension status, the configured backend
URLs, and buttons to open Settings / refresh PIR parameters. **Note:** the iOS
Simulator does not fully exercise the call-time Live Caller ID Lookup subsystem,
so it validates the build, the SDK wiring, and Settings registration - not an
actual incoming-call lookup. For that, use a real device.

## Run on your own iPhone over USB (LCID-only dev sample — not production)

> **Production CallerAPI** requires Call Directory + paid Apple Developer account.
> See [`../../react-native/IOS-INTEGRATION.md`](../../react-native/IOS-INTEGRATION.md).

This LCID-only demo can run on a Personal Team for SDK hacking. In Xcode:

1. Select the `CallerAPIDemo` target ▸ **Signing & Capabilities** ▸ check
   **Automatically manage signing** ▸ choose your personal team (your Apple ID).
   Do the same for the `LiveLookupExtension` target.
2. The bundle IDs `com.callerapi.demo[.LiveLookupExtension]` may already be
   taken - change them to something unique (e.g. `com.<you>.lcidtest`) in
   `project.yml` (then `xcodegen generate`) or directly in Xcode. Keep the
   extension ID as `<hostID>.LiveLookupExtension` and update `extensionID` in
   `ContentView.swift` to match.
3. Plug in the iPhone, select it as the run destination, hit ▶. First run: trust
   the developer profile under Settings ▸ General ▸ VPN & Device Management.
4. On the phone: **Settings → Phone → Call Blocking & Identification**,
   enable **CallerAPI Live Lookup**.

On a build installed straight from Xcode, the system **bypasses Apple's
Oblivious relay** and talks to the service/issuer URLs directly - so you can see
real `/config`, `/key`, `/queries` traffic hit `pir.callerapi.com` from the
device without relay enrollment. (If Xcode refuses to add the Live Caller ID
Lookup capability under a free Personal Team, that capability needs the paid
program - see below.)

## When you actually need the $99 Apple Developer Program

- **Relay enrollment** - for real call traffic to flow through Apple's Oblivious
  relay to your gateway (`https://gateway.callerapi.com`) instead of the dev-only
  direct path.
- **TestFlight / App Store distribution** and selling to MVNOs.
- Possibly the Live Caller ID Lookup **capability** itself, if a free Personal
  Team can't add it.

The gateway, issuer, and PIR origin are all already live and validated
(`go run ./cmd/ohttpcheck` against production), so the backend is ready the
moment you enroll.
