import SwiftUI

// Minimal host app for the CallerAPI Live Caller ID Lookup extension.
//
// The host app does NOT perform any caller lookups itself - that is the
// extension's (well, the system's) job. The host app exists only to:
//   • bundle + embed the Live Caller ID Lookup extension,
//   • show whether the user has enabled it in Settings,
//   • deep-link the user into Settings to enable it,
//   • (optionally) push a per-user tier token to the extension via App Group.
@main
struct CallerAPIDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
