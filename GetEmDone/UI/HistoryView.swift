import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HouseholdStore

    var body: some View {
        Group {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Submissions, approvals, resets, and overrides will appear here.")
                )
            } else {
                List(store.history) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: symbol(for: event.kind))
                            .foregroundStyle(tint(for: event.kind))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.message)
                            Text(event.date, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private func symbol(for kind: ActivityEvent.Kind) -> String {
        switch kind {
        case .submitted: "paperplane.fill"
        case .approved: "checkmark.circle.fill"
        case .redoRequested: "arrow.counterclockwise.circle.fill"
        case .override: "key.fill"
        case .dailyReset: "sunrise.fill"
        case .choreCreated: "plus.circle.fill"
        case .choreRemoved: "minus.circle.fill"
        }
    }

    private func tint(for kind: ActivityEvent.Kind) -> Color {
        switch kind {
        case .approved: GEDTheme.mint
        case .redoRequested, .choreRemoved: .red
        case .override, .submitted: GEDTheme.warm
        default: GEDTheme.accent
        }
    }
}
