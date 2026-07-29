import Foundation
import IdentityLookup
import CallerAPILiveCallerID

// The entire Live Caller ID Lookup extension. The system reads `context` once
// when the user enables the extension, then runs the full PIR / Privacy Pass /
// Oblivious HTTP protocol against the CallerAPI backend on every incoming call.
// No call-time code runs here.
@main
struct CallerAPILiveLookupExtension: LiveCallerIDLookupProtocol {
    var context: LiveCallerIDLookupExtensionContext {
        CallerAPILiveCallerID.makeExtensionContext()
    }
}
