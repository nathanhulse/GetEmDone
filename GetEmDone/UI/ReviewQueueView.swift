import SwiftUI

struct ReviewQueueView: View {
    @ObservedObject var store: HouseholdStore
    @State private var redoChore: Chore?
    @State private var showOverride = false

    private var pending: [Chore] { store.chores.filter { $0.state == .submitted } }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "You’re caught up",
                    systemImage: "checkmark.seal.fill",
                    description: Text("New check-ins will appear here for review.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(pending) { chore in reviewCard(chore) }
                        Button("Approve all submitted") { Task { await store.approveSubmitted() } }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding()
                }
                .background(GEDTheme.canvas)
            }
        }
        .navigationTitle("Review")
        .toolbar { Button("Override", systemImage: "key.fill") { showOverride = true } }
        .sheet(item: $redoChore) { chore in RedoNoteView(chore: chore, store: store) }
        .sheet(isPresented: $showOverride) { OverrideView(store: store) }
    }

    private func reviewCard(_ chore: Chore) -> some View {
        GEDCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(chore.title, systemImage: chore.evidence.symbol).font(.headline)
                    Spacer()
                    StatusPill(text: "Submitted", symbol: "paperplane.fill", tint: GEDTheme.warm)
                }
                evidenceSummary(chore)
                HStack {
                    Button("Needs another try") { redoChore = chore }.buttonStyle(.bordered)
                    Button("Approve") {
                        store.approve(chore)
                        Task { await store.reconcilePolicy() }
                    }
                    .buttonStyle(.borderedProminent).tint(GEDTheme.mint)
                }
            }
        }
    }

    @ViewBuilder private func evidenceSummary(_ chore: Chore) -> some View {
        switch chore.evidenceProgress {
        case .photoReady:
            Label("Photo attached and ready to review", systemImage: "photo.fill")
        case .timer(let seconds):
            Label("Practiced for \(seconds / 60)m \(seconds % 60)s", systemImage: "timer")
        case .none:
            Label("Child check-in—no media required", systemImage: "checkmark.circle")
        }
    }
}

private struct RedoNoteView: View {
    @Environment(\.dismiss) private var dismiss
    let chore: Chore
    @ObservedObject var store: HouseholdStore
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("What needs another try?") {
                    TextField("A short, encouraging note", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(chore.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { store.requestRedo(chore, note: note); dismiss() }
                }
            }
        }
    }
}

private struct OverrideView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: HouseholdStore
    @State private var target: OverrideTarget = .appleTV

    var body: some View {
        NavigationStack {
            Form {
                Section("Temporarily unlock") {
                    Picker("Target", selection: $target) {
                        ForEach(OverrideTarget.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Text("This does not mark chores complete. The next daily reset restores the normal policy.")
                }
            }
            .navigationTitle("Parent override")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock") { store.applyOverride(target: target); dismiss() }
                }
            }
        }
    }
}
