import SwiftUI

struct TodayView: View {
    @ObservedObject var store: HouseholdStore
    @State private var sheet: TodaySheet?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                roleSummary
                accessCard
                choresSection
                if store.role == .parent { parentActions }
            }
            .padding()
        }
        .background {
            LinearGradient(
                colors: [GEDTheme.accent(for: store.role).opacity(0.10), GEDTheme.canvas, GEDTheme.canvas],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Today")
        .toolbar {
            if store.role == .parent {
            ToolbarItem(placement: .topBarLeading) {
                Button("Add", systemImage: "plus") { sheet = .newChore }
            }
            }
#if DEBUG
            roleMenu
#endif
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .newChore: AddChoreView(store: store)
            case .evidence(let chore): EvidenceCheckInView(chore: chore, store: store)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var roleSummary: some View {
        HStack(spacing: 10) {
            MetricTile(
                value: "\(store.chores.filter { $0.state == .approved }.count)",
                label: store.role == .parent ? "Approved" : "All done",
                symbol: "checkmark.seal.fill",
                tint: GEDTheme.mint
            )
            MetricTile(
                value: "\(store.chores.filter { $0.state == .submitted }.count)",
                label: store.role == .parent ? "To review" : "Waiting on parent",
                symbol: "tray.full.fill",
                tint: GEDTheme.warm
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.role == .parent ? "\(store.childName)’s morning" : "Good morning, \(store.childName)")
                    .font(.title2.bold())
                Text("\(store.completedCount) of \(store.todaysChores.count) responsibilities checked in")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(store.progress * 100))%")
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(GEDTheme.accent)
        }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: accessSymbol)
                    .font(.title2)
                    .foregroundStyle(accessTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.accessState.title).font(.headline)
                    Text(accessDetail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ProgressView(value: store.progress)
                .tint(accessTint)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if store.role == .child, case .locked = store.accessState {
                Text(nextStep)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GEDTheme.childAccent)
                    .padding(12)
            }
        }
    }

    private var choresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RESPONSIBILITIES")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            ForEach(store.todaysChores) { chore in
                ChoreRow(chore: chore, role: store.role) {
                    if store.role == .parent {
                        store.approve(chore)
                    } else if chore.evidence == .checkIn {
                        store.submit(chore)
                    } else {
                        sheet = .evidence(chore)
                    }
                    Task { await store.reconcilePolicy() }
                } onRedo: {
                    store.requestRedo(chore)
                    Task { await store.reconcilePolicy() }
                }
            }
        }
    }

    private var parentActions: some View {
        VStack(spacing: 10) {
            Button("Approve submitted chores") { Task { await store.approveSubmitted() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!store.canApproveAll || store.isApplyingPolicy)
            Button("Parent override: unlock today") { Task { await store.unlockForToday() } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GEDTheme.accent)
        }
    }

    @ToolbarContentBuilder private var roleMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Preview as", selection: $store.role) {
                    ForEach(HouseholdRole.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label(store.role.title, systemImage: store.role == .parent ? "person.badge.key" : "figure.child")
            }
        }
    }

    private var accessSymbol: String {
        if case .unlocked = store.accessState { return "sparkles" }
        return store.accessState == .awaitingApproval ? "clock.badge.checkmark" : "lock.fill"
    }

    private var accessTint: Color {
        if case .unlocked = store.accessState { return GEDTheme.mint }
        return store.accessState == .awaitingApproval ? GEDTheme.warm : GEDTheme.accent
    }

    private var accessDetail: String {
        switch store.accessState {
        case .locked: "Entertainment stays paused until today’s list is done."
        case .awaitingApproval: "A parent can review the submitted items now."
        case .unlocked: "Apps, websites, and the Family Room TV are available."
        }
    }

    private var nextStep: String {
        let remaining = store.todaysChores.filter { $0.state == .waiting }.count
        return remaining == 1 ? "One left!" : "\(remaining) left"
    }
}

private enum TodaySheet: Identifiable {
    case newChore
    case evidence(Chore)

    var id: String {
        switch self {
        case .newChore: "new"
        case .evidence(let chore): chore.id.uuidString
        }
    }
}

private struct AddChoreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: HouseholdStore
    @State private var title = ""
    @State private var detail = ""
    @State private var evidence: ChoreEvidence = .checkIn
    @State private var activeWeekdays = Set(1...7)

    var body: some View {
        NavigationStack {
            Form {
                Section("Responsibility") {
                    TextField("Make your bed", text: $title)
                    TextField("What counts as done?", text: $detail)
                    Picker("Check-in", selection: $evidence) {
                        ForEach(ChoreEvidence.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                Section("Repeats") {
                    ForEach(Array(Calendar.current.shortWeekdaySymbols.enumerated()), id: \.offset) { index, day in
                        Toggle(day, isOn: weekdayBinding(index + 1))
                    }
                }
            }
            .navigationTitle("New responsibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addChore(title: title, detail: detail, evidence: evidence, activeWeekdays: activeWeekdays)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeWeekdays.isEmpty)
                }
            }
        }
    }

    private func weekdayBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { activeWeekdays.contains(day) },
            set: { enabled in
                if enabled {
                    activeWeekdays.insert(day)
                } else {
                    activeWeekdays.remove(day)
                }
            }
        )
    }
}

private struct ChoreRow: View {
    let chore: Chore
    let role: HouseholdRole
    let onPrimary: () -> Void
    let onRedo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: stateSymbol)
                .font(.title2)
                .foregroundStyle(stateTint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title).font(.headline)
                Label(chore.detail, systemImage: chore.evidence.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            action
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var action: some View {
        switch (role, chore.state) {
        case (_, .approved): StatusPill(text: "Done", symbol: "checkmark", tint: GEDTheme.mint)
        case (.parent, .submitted):
            Menu {
                Button("Approve", action: onPrimary)
                Button("Ask to redo", role: .destructive, action: onRedo)
            } label: { StatusPill(text: "Review", symbol: "eye", tint: GEDTheme.warm) }
        case (.parent, .waiting): StatusPill(text: "Waiting", symbol: "hourglass", tint: .secondary)
        case (.child, .submitted): StatusPill(text: "Sent", symbol: "paperplane", tint: GEDTheme.warm)
        case (.child, .waiting):
            Button("Check in", action: onPrimary)
                .buttonStyle(.borderedProminent)
                .tint(GEDTheme.accent)
        }
    }

    private var stateSymbol: String {
        switch chore.state {
        case .waiting: chore.evidence.symbol
        case .submitted: "clock.fill"
        case .approved: "checkmark.circle.fill"
        }
    }

    private var stateTint: Color {
        switch chore.state {
        case .waiting: GEDTheme.accent
        case .submitted: GEDTheme.warm
        case .approved: GEDTheme.mint
        }
    }
}
