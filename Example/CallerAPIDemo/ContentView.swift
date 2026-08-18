import SwiftUI
import CallerAPILiveCallerID

struct ContentView: View {
    // Must match the extension target's bundle identifier (see project.yml).
    private let extensionID = "com.callerapi.demo.LiveLookupExtension"

    @Environment(\.scenePhase) private var scenePhase
    @State private var statusText = "Checking…"
    @State private var isEnabled = false
    @State private var lastMessage = ""
    @State private var busy = false

    private let config = CallerAPILiveCallerIDConfiguration.production

    private let manualSettingsPath =
        "Open Settings ▸ Apps ▸ Phone ▸ Call Blocking & Identification and enable CallerAPI Live Lookup."

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
                    Button("Refresh status", action: peekStatus)
                    Button("Open Settings") {
                        Task { await runOpenSettings() }
                    }
                    .disabled(busy)
                }

                Section("CallerAPI backend") {
                    LabeledContent("Service URL") {
                        Text(config.serviceURL.absoluteString).font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Issuer URL") {
                        Text(config.tokenIssuerURL.absoluteString).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Refresh PIR parameters") {
                        Task { await runReprovision(clearCache: false) }
                    }
                    .disabled(busy)
                    Button("Reset lookup cache + refresh") {
                        Task { await runReprovision(clearCache: true) }
                    }
                    .disabled(busy)
                }

                if !lastMessage.isEmpty {
                    Section("Last result") {
                        Text(lastMessage).font(.footnote)
                    }
                }

                Section {
                    Text("This screen does not talk to CallDirectory on launch. Enable the extension in Settings, then tap Refresh PIR parameters. Use Reset only after a server package rebuild. Then place a call.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CallerAPI LCID")
            .task { await pollStatus() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !busy else { return }
                peekStatus()
            }
        }
    }

    private func peekStatus() {
        let disabled = CallerAPILiveCallerID.isDisabled(forExtensionWithIdentifier: extensionID)
        isEnabled = !disabled
        statusText = disabled ? "Disabled. Enable in Settings." : "Enabled"
    }

    /// Status is a query, not a spawn, so polling it is cheap. The system
    /// answers Cocoa 4099 for a while after boot and after an install.
    private func pollStatus() async {
        for attempt in 1...30 {
            let disabled = CallerAPILiveCallerID.isDisabled(forExtensionWithIdentifier: extensionID)
            NSLog("[CallerAPI][DEMO] status poll %d: disabled=%@", attempt, disabled ? "true" : "false")
            isEnabled = !disabled
            statusText = disabled ? "Disabled. Enable in Settings." : "Enabled"
            if !disabled {
                await runReprovision(clearCache: false)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func runOpenSettings() async {
        do {
            try await CallerAPILiveCallerID.openSettings()
            lastMessage = "Opened Settings."
        } catch {
            lastMessage = manualSettingsPath
        }
    }

    private func runReprovision(clearCache: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await CallerAPILiveCallerID.reprovision(
                forExtensionWithIdentifier: extensionID,
                clearCachedLookups: clearCache
            )
            peekStatus()
            lastMessage = clearCache
                ? "Cleared lookup cache and refreshed PIR parameters."
                : "Refreshed PIR parameters."
        } catch {
            peekStatus()
            if CallerAPILiveCallerID.isCallDirectoryUnavailable(error) {
                lastMessage = "CallDirectory is not up yet. Wait a few seconds, then tap Refresh PIR parameters."
            } else if CallerAPILiveCallerID.isStaleExtensionConnection(error) {
                lastMessage = "ExtensionKit dropped the connection. Tap Refresh PIR parameters again."
            } else {
                lastMessage = "Refresh failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
}
