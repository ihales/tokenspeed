import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @ViewState private var loginStatus = SMAppService.mainApp.status
    @ViewState private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open TokenSpeed at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: setOpenAtLogin
                ))
                .disabled(!isInstalledApp)
                if let note = loginNote {
                    note
                }
            } header: {
                Text("Startup")
            }

            Section {
                LabeledContent("Refresh", value: "Every minute")
                LabeledContent("Data source") {
                    Link("OpenRouter", destination: URL(string: "https://openrouter.ai/models")!)
                }
                LabeledContent("API key", value: "Not needed")
            } header: {
                Text("Data")
            } footer: {
                Text("Median TPS comes from the public feed behind OpenRouter’s provider pages and uptime from the OpenRouter Endpoints API. TokenSpeed records TPS every 5 minutes to draw its 24-hour trend lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    /// Login items need a real app bundle; `swift run` launches a bare executable.
    private var isInstalledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private var loginNote: AnyView? {
        if !isInstalledApp {
            return AnyView(note("Run TokenSpeed from its app bundle to enable this. Use “task install” to put it in Applications.",
                                icon: "info.circle"))
        }
        if let loginError {
            return AnyView(note(loginError, icon: "exclamationmark.triangle.fill", tint: .orange))
        }
        if loginStatus == .requiresApproval {
            return AnyView(HStack {
                note("Allow TokenSpeed in System Settings → General → Login Items.", icon: "exclamationmark.triangle.fill",
                     tint: .orange)
                Spacer()
                Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            })
        }
        return nil
    }

    private func note(_ text: String, icon: String, tint: Color = .secondary) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn’t update the login item: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}
