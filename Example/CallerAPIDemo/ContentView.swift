import SwiftUI
import CallerAPILiveCallerID

struct ContentView: View {
    // Must match the extension target's bundle identifier (see project.yml).
    private let extensionID = "com.callerapi.demo.LiveLookupExtension"

    @State private var statusText = "Checking…"
    @State private var isEnabled = false
    @State private var lastMessage = ""

    private let config = CallerAPILiveCallerIDConfiguration.production

    // There is no public deep-link to "Call Blocking & Identification".
    // `openSettings()` routes through CallKit's settings helper
    // (com.apple.CallKit.CallDirectory) and frequently fails with
    // "Couldn't communicate with a helper application" - so we always show the
    // manual path as the reliable fallback.
    private let manualSettingsPath =
        "Open Settings ▸ Apps ▸ Phone ▸ Call Blocking & Identification and enable CallerAPI Live Lookup. (Toggle it off then on to flush cached results.)"

    var body: some View {
        NavigationStack {
            List {
                Section("Extension") {
                    LabeledContent("Bundle ID") {
                        Text(extensionID).font(.footnote.monospaced()).foregroundStyle(.secondary)
                    }
                    LabeledContent("Status") {
                        Text(statusText).foregroundStyle(isEnabled ? .green : .orange)
                    }
                    Button("Refresh status", action: refreshStatus)
                    Button("Open Settings to enable") {
                        Task { await runOpenSettings() }
                    }
                }

                Section("CallerAPI backend") {
                    LabeledContent("Service URL") {
                        Text(config.serviceURL.absoluteString).font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Issuer URL") {
                        Text(config.tokenIssuerURL.absoluteString).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Refresh PIR parameters") {
                        Task { await runRefreshParams() }
                    }
                }

                if !lastMessage.isEmpty {
                    Section("Last result") {
                        Text(lastMessage).font(.footnote)
                    }
                }

                Section {
                    Text("Enable the extension under Settings ▸ Apps ▸ Phone ▸ Call Blocking & Identification, then place/simulate a call. On a development build the system talks to the service URLs directly (Apple's relay is bypassed).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CallerAPI LCID")
            .onAppear(perform: refreshStatus)
            .task(id: isEnabled) { await prewarmIfEnabled() }
        }
    }

    private func refreshStatus() {
        let disabled = CallerAPILiveCallerID.isDisabled(forExtensionWithIdentifier: extensionID)
        isEnabled = !disabled
        statusText = disabled ? "Disabled - enable in Settings" : "Enabled"
    }

    /// Pre-warm PIR provisioning at app launch (and whenever the extension flips
    /// to enabled) so the system fetches config + uploads eval keys BEFORE the
    /// first incoming call. This is the only lever Apple gives the host app to
    /// pull the one-time cold-start work forward off the first call's path; the
    /// PIR daemon still owns the actual scheduling.
    private func prewarmIfEnabled() async {
        guard isEnabled else { return }
        try? await CallerAPILiveCallerID.refreshPIRParameters(forExtensionWithIdentifier: extensionID)
    }

    private func runOpenSettings() async {
        do {
            try await CallerAPILiveCallerID.openSettings()
            lastMessage = "Opened Settings."
        } catch {
            // openSettings() goes through CallKit's flaky settings helper; on
            // failure (the common case) fall back to the manual instructions
            // rather than dumping the raw XPC error on the user.
            lastMessage = manualSettingsPath
        }
    }

    private func runRefreshParams() async {
        do {
            try await CallerAPILiveCallerID.refreshPIRParameters(forExtensionWithIdentifier: extensionID)
            lastMessage = "Requested PIR parameter refresh."
        } catch {
            lastMessage = "refreshPIRParameters failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
