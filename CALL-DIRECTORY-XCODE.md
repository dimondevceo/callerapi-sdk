# Call Directory extension — Xcode reference

**Required** for CallerAPI iOS. Ships in every zip at **`ios/CallDirectoryExtension/`**.

Automated wiring: `setup_callerapi_ios.sh` in the RN/Flutter package (recommended).

---

## Files in `ios/CallDirectoryExtension/`

| File | Role |
| --- | --- |
| `CallDirectoryHandler.swift` | Extension entry (`CALLERAPI_BRIDGING_ONLY`) |
| `AppConfig.swift` | App group + extension bundle id |
| `Bridge.h` | C core bridging |
| `Info.plist` | CallKit NSExtension |
| `CallDirectoryExtension.entitlements` | App Group + Keychain |
| `Host.entitlements` | Same groups on **host** app |

---

## Manual Xcode checklist

1. **Call Directory Extension** target — `com.yourco.app.CallDirectory`
2. Copy template files; link **CallerAPI.xcframework** + **CallKit** + `CallDirectory.swift` + `CallerAPI.swift` + `Entitlement.swift`
3. Bridging header, `CALLERAPI_BRIDGING_ONLY`, `-lz`, Info.plist Preprocessor **YES**
4. Host + extension **same** App Group + Keychain entitlements
5. Embed in host **PlugIns** (not ExtensionKit)
6. Info.plist keys — see the table below. Getting the target wrong is the usual
   cause of "sync OK, empty list"
7. **Settings → Phone** → enable Call Directory → `syncCallDirectory()` / `CallDirectory.sync()`

---

## Info.plist keys

Which target a key goes on matters, because each is read from the `Bundle.main` of
whichever process reads it.

| Key | Target | Read by |
| --- | --- | --- |
| `CallerAPISDKKey`, `CallerAPISDKSecret` | Host | The host app, to authenticate |
| `CallerAPIKeychainAccessGroup` | **Extension** | `CallDirectoryHandler.swift`, to find the at-rest key |
| `CallerAPIAppGroup` | Host | Live Caller ID only. The native Call Directory path takes the group from `AppConfig.swift` |
| `CallerAPICallDirectoryExtensionBundleID` | Host | The Flutter and React Native bootstrap only. Native builds take it from `AppConfig.swift` |

On a native integration, set the App Group and extension bundle id in
`AppConfig.swift`. The last two keys above exist for the wrapper packages and for
LCID, and adding them to a native host app changes nothing.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Toggle missing | Paid team; PlugIns embed; nested bundle id |
| Sync OK, empty list | Host and extension disagree on `CallerAPIKeychainAccessGroup` or the App Group. Filter the device console for subsystem `com.callerapi.sdk`: the extension logs the failure |
| Linker `_inflate` | `-lz` on extension |
| `callerapi_*` undefined | xcframework + Bridge.h |
