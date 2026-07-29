import Foundation
import IdentityLookup
import CallerAPILiveCallerID

// Live Caller ID Lookup app extension entry point.
//
// This is the entire extension. The iOS system reads `context` once when the
// user enables the extension in Settings, then runs the full Live Caller ID
// Lookup protocol (Privacy Pass + Oblivious HTTP + keyword PIR) against the
// CallerAPI backend itself on every incoming call. No call-time code runs here.
//
// Copy this file into a new "Live Caller ID Lookup Extension" target in your
// app (File ▸ New ▸ Target). See ../INTEGRATION.md for the full walkthrough.
@main
struct CallerAPILiveLookupExtension: LiveCallerIDLookupProtocol {

    init() {
        // OPTIONAL: only needed if your host app pushes a per-user tier token
        // (or staging URLs) to this extension via a shared App Group. Use the
        // SAME identifier in the host app. Leave commented for the zero-config
        // production default.
        //
        // CallerAPILiveCallerID.appGroupIdentifier = "group.com.yourco.app"
    }

    var context: LiveCallerIDLookupExtensionContext {
        CallerAPILiveCallerID.makeExtensionContext()
    }
}
