import SwiftUI

struct ChildStatusView: View {
    @ObservedObject var store: HouseholdStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GEDCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(store.accessState.title, systemImage: accessSymbol)
                            .font(.title2.bold())
                            .foregroundStyle(accessTint)
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("WHAT’S PAUSED").font(.caption.bold()).foregroundStyle(.secondary)
                    statusRow("Entertainment apps", symbol: "apps.iphone", paused: store.enforcement.phoneAppsShielded)
                    statusRow("Distracting websites", symbol: "safari", paused: store.enforcement.webDistractionsFiltered)
                    statusRow("Family Room TV", symbol: "appletv.fill", paused: store.enforcement.appleTVPaused)
                }

                GEDCard {
                    Label("Need help? Ask a parent to review your list or use their recovery code.", systemImage: "person.2.fill")
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .background(GEDTheme.canvas)
        .navigationTitle("My access")
    }

    private func statusRow(_ title: String, symbol: String, paused: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(GEDTheme.childAccent)
            Text(title).font(.headline)
            Spacer()
            StatusPill(text: paused ? "Paused" : "Available", symbol: paused ? "pause.fill" : "checkmark", tint: paused ? GEDTheme.warm : GEDTheme.mint)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var accessSymbol: String {
        if case .unlocked = store.accessState { return "sparkles" }
        return "lock.shield.fill"
    }

    private var accessTint: Color {
        if case .unlocked = store.accessState { return GEDTheme.mint }
        return GEDTheme.childAccent
    }

    private var statusMessage: String {
        switch store.accessState {
        case .locked: "Finish today’s responsibilities, then send them to your parent."
        case .awaitingApproval: "You did your part. Your parent has your check-in."
        case .unlocked: "Nice work—your entertainment is available."
        }
    }
}
