# Call Directory extension template

Ships in every SDK zip at **`ios/CallDirectoryExtension/`**. Copied into RN/Flutter apps by
`setup_callerapi_ios.sh` from `ios/templates/CallDirectoryExtension/`.

| File | Purpose |
| --- | --- |
| `CallDirectoryHandler.swift` | Extension entry (`CALLERAPI_BRIDGING_ONLY` + Bridge.h) |
| `AppConfig.swift` | App group + extension bundle id (setup script rewrites from host id) |
| `Bridge.h` | `#include "callerapi.h"` |
| `Info.plist` | CallKit NSExtension + keychain plist key |
| `CallDirectoryExtension.entitlements` | App Group + Keychain |
| `Host.entitlements` | Same groups for the **host** app |

Full steps: [`../CALL-DIRECTORY-XCODE.md`](../CALL-DIRECTORY-XCODE.md).  
RN/Flutter: [`../../react-native/IOS-INTEGRATION.md`](../../react-native/IOS-INTEGRATION.md) or [`../../flutter/IOS-INTEGRATION.md`](../../flutter/IOS-INTEGRATION.md).
