import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: HouseholdStore

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: healthSymbol).foregroundStyle(healthTint)
                    VStack(alignment: .leading) {
                        Text(store.protectionHealth.title).font(.headline)
                        if case .degraded(let message) = store.protectionHealth {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if store.protectionHealth == .applying { ProgressView() }
                }
                Button("Check protection now") { Task { await store.reconcilePolicy() } }
            } header: { Text("Protection health") }

            Section {
                ForEach(store.devices) { device in
                    DeviceRow(device: device, enforcement: store.enforcement)
                }
            } header: {
                Text("Protected devices")
            } footer: {
                Text("Apple TV controls require a compatible home network. GetEmDone never changes the whole household’s internet by default.")
            }

            Section("Internet policy") {
                Label("Safety filtering always on", systemImage: "checkmark.shield.fill")
                LabeledContent("Chore-time distractions", value: store.enforcement.webDistractionsFiltered ? "Filtered" : "Available")
            }

            Section {
                Button("Run connection test") { }
            } footer: {
                Text("This prototype simulates device enforcement. Production router adapters are a later certification gate.")
            }
        }
        .navigationTitle("Devices")
    }

    private var healthSymbol: String {
        switch store.protectionHealth {
        case .unknown: "questionmark.circle"
        case .applying: "arrow.triangle.2.circlepath"
        case .healthy: "checkmark.shield.fill"
        case .degraded: "exclamationmark.triangle.fill"
        }
    }

    private var healthTint: Color {
        switch store.protectionHealth {
        case .healthy: GEDTheme.mint
        case .degraded: .red
        case .applying: GEDTheme.warm
        case .unknown: .secondary
        }
    }
}

private struct DeviceRow: View {
    let device: ManagedDevice
    let enforcement: EnforcementSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind == .appleTV ? "appletv.fill" : "iphone")
                .font(.title2)
                .foregroundStyle(GEDTheme.accent)
                .frame(width: 34)
            VStack(alignment: .leading) {
                Text(device.name).font(.headline)
                Text(device.kind.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: isPaused ? "Paused" : "Available", symbol: isPaused ? "pause.fill" : "checkmark", tint: isPaused ? GEDTheme.warm : GEDTheme.mint)
        }
    }

    private var isPaused: Bool {
        device.kind == .appleTV ? enforcement.appleTVPaused : enforcement.phoneAppsShielded
    }
}
