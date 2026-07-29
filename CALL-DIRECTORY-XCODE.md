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
2. Copy template files; link **CallerAPI.xcframework** + **CallKit** + `CallDirectory.swift` + `CallerAPI.swift`
3. Bridging header, `CALLERAPI_BRIDGING_ONLY`, `-lz`, Info.plist Preprocessor **YES**
4. Host + extension **same** App Group + Keychain entitlements
5. Embed in host **PlugIns** (not ExtensionKit)
6. Host plist: `CallerAPIAppGroup`, `CallerAPICallDirectoryExtensionBundleID`, `CallerAPIKeychainAccessGroup`
7. **Settings → Phone** → enable Call Directory → `syncCallDirectory()` / `CallDirectory.sync()`

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Toggle missing | Paid team; PlugIns embed; nested bundle id |
| Sync OK, empty list | Keychain / App Group mismatch |
| Linker `_inflate` | `-lz` on extension |
| `callerapi_*` undefined | xcframework + Bridge.h |
