import SwiftUI

struct RoutineView: View {
    @ObservedObject var store: HouseholdStore
    @State private var selectedChore: Chore?

    var body: some View {
        List {
            Section("Active responsibilities") {
                ForEach(store.chores.filter { !$0.isArchived }) { chore in
                    Button { selectedChore = chore } label: {
                        routineRow(chore)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Archive") { store.setArchived(true, chore: chore) }
                            .tint(.orange)
                    }
                }
            }
            if store.chores.contains(where: \.isArchived) {
                Section("Archived") {
                    ForEach(store.chores.filter(\.isArchived)) { chore in
                        HStack {
                            Text(chore.title).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore") { store.setArchived(false, chore: chore) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Routine")
        .toolbar { Button("Add", systemImage: "plus") { selectedChore = Chore(title: "", detail: "", evidence: .checkIn) } }
        .sheet(item: $selectedChore) { chore in
            RoutineEditorView(chore: chore, isNew: !store.chores.contains(where: { $0.id == chore.id }), store: store)
        }
    }

    private func routineRow(_ chore: Chore) -> some View {
        HStack(spacing: 12) {
            Image(systemName: chore.evidence.symbol).foregroundStyle(GEDTheme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(chore.title).font(.headline)
                Text(chore.recurrenceLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
    }
}

private struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var chore: Chore
    let isNew: Bool
    @ObservedObject var store: HouseholdStore
    @State private var hasDueTime = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Responsibility") {
                    TextField("Title", text: $chore.title)
                    TextField("What counts as done?", text: $chore.detail)
                    Picker("Check-in", selection: $chore.evidence) {
                        ForEach(ChoreEvidence.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section("Schedule") {
                    Picker("Repeat", selection: recurrencePreset) {
                        Text("Every day").tag(0)
                        Text("Weekdays").tag(1)
                        Text("Weekends").tag(2)
                    }
                    Toggle("Show a due time", isOn: $hasDueTime)
                    if hasDueTime {
                        DatePicker("Due", selection: dueDate, displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                    Text("Changes affect the next daily reset. Today’s completed work stays intact.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "New responsibility" : "Edit responsibility")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { hasDueTime = chore.dueMinutes != nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNew {
                            store.addChore(title: chore.title, detail: chore.detail, evidence: chore.evidence, activeWeekdays: chore.activeWeekdays)
                        } else { store.updateChore(chore) }
                        dismiss()
                    }
                    .disabled(chore.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var recurrencePreset: Binding<Int> {
        Binding(get: {
            chore.activeWeekdays == Set(2...6) ? 1 : (chore.activeWeekdays == [1, 7] ? 2 : 0)
        }, set: { preset in
            chore.activeWeekdays = preset == 1 ? Set(2...6) : (preset == 2 ? [1, 7] : Set(1...7))
        })
    }

    private var dueDate: Binding<Date> {
        Binding(get: {
            Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval((chore.dueMinutes ?? 8 * 60) * 60))
        }, set: { date in
            let values = Calendar.current.dateComponents([.hour, .minute], from: date)
            chore.dueMinutes = (values.hour ?? 0) * 60 + (values.minute ?? 0)
        })
    }
}
