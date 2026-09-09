import Foundation
import Combine

@MainActor
final class HouseholdStore: ObservableObject {
    @Published var role: HouseholdRole
    @Published var childName: String
    @Published var chores: [Chore]
    @Published var devices: [ManagedDevice]
    @Published var history: [ActivityEvent]
    @Published var enforcement: EnforcementSnapshot
    @Published var isApplyingPolicy = false
    @Published var errorMessage: String?

    private let enforcementService: any EnforcementService
    private let persistence: any HouseholdPersistence

    init(
        role: HouseholdRole,
        childName: String,
        chores: [Chore],
        devices: [ManagedDevice],
        history: [ActivityEvent] = [],
        enforcementService: any EnforcementService = DemoEnforcementService(),
        persistence: any HouseholdPersistence = MemoryHouseholdPersistence()
    ) {
        self.role = role
        self.childName = childName
        self.chores = chores
        self.devices = devices
        self.history = history
        self.enforcementService = enforcementService
        self.persistence = persistence
        self.enforcement = .init(phoneAppsShielded: true, webDistractionsFiltered: true, appleTVPaused: true)
    }

    var accessState: AccessState {
        let active = activeChores()
        guard !active.isEmpty else { return .locked }
        if active.allSatisfy({ $0.state == .approved }) { return .unlocked(until: nil) }
        if active.allSatisfy({ $0.state != .waiting }) { return .awaitingApproval }
        return .locked
    }

    var todaysChores: [Chore] { activeChores() }
    var completedCount: Int { todaysChores.filter { $0.state != .waiting }.count }
    var progress: Double { todaysChores.isEmpty ? 0 : Double(completedCount) / Double(todaysChores.count) }
    var canApproveAll: Bool { todaysChores.contains { $0.state == .submitted } }

    func submit(_ chore: Chore) {
        guard let current = chores.first(where: { $0.id == chore.id }), current.state == .waiting, current.canSubmit else { return }
        update(chore.id) { $0.state = .submitted }
        record(.submitted, "\(chore.title) was submitted")
        persistSoon()
    }

    func attachPhoto(to chore: Chore) {
        update(chore.id) { $0.evidenceProgress = .photoReady }
        persistSoon()
    }

    func recordPractice(seconds: Int, for chore: Chore) {
        guard seconds > 0 else { return }
        update(chore.id) { $0.evidenceProgress = .timer(seconds: seconds) }
        persistSoon()
    }

    func approve(_ chore: Chore) {
        update(chore.id) { $0.state = .approved }
        record(.approved, "\(chore.title) was approved")
        persistSoon()
    }

    func requestRedo(_ chore: Chore) {
        update(chore.id) { $0.state = .waiting }
        record(.redoRequested, "\(chore.title) needs another try")
        persistSoon()
    }

    func addChore(title: String, detail: String, evidence: ChoreEvidence, activeWeekdays: Set<Int>) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        chores.append(Chore(title: trimmedTitle, detail: detail, evidence: evidence, activeWeekdays: activeWeekdays))
        record(.choreCreated, "\(trimmedTitle) was added")
        persistSoon()
    }

    func removeChores(at offsets: IndexSet) {
        let names = offsets.compactMap { chores.indices.contains($0) ? chores[$0].title : nil }
        chores.remove(atOffsets: offsets)
        names.forEach { record(.choreRemoved, "\($0) was removed") }
        persistSoon()
    }

    func updateChore(_ chore: Chore) {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }) else { return }
        var cleaned = chore
        cleaned.title = chore.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.title.isEmpty, !cleaned.activeWeekdays.isEmpty else { return }
        chores[index] = cleaned
        record(.choreEdited, "\(cleaned.title) was updated")
        persistSoon()
    }

    func setArchived(_ archived: Bool, chore: Chore) {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }) else { return }
        chores[index].isArchived = archived
        record(.choreEdited, "\(chore.title) was \(archived ? "archived" : "restored")")
        persistSoon()
    }

    func activeChores(on date: Date = .now, calendar: Calendar = .current) -> [Chore] {
        let weekday = calendar.component(.weekday, from: date)
        return chores.filter { !$0.isArchived && $0.activeWeekdays.contains(weekday) }
    }

    func approveSubmitted() async {
        for index in chores.indices where chores[index].state == .submitted {
            record(.approved, "\(chores[index].title) was approved")
            chores[index].state = .approved
        }
        await persist()
        await reconcilePolicy()
    }

    func unlockForToday() async {
        for index in chores.indices { chores[index].state = .approved }
        record(.override, "Parent unlocked entertainment for today")
        await persist()
        await reconcilePolicy()
    }

    func resetDay() async {
        for index in chores.indices { chores[index].state = .waiting }
        record(.dailyReset, "A new daily routine started")
        await persist()
        await reconcilePolicy()
    }

    func load() async {
        do {
            guard let snapshot = try await persistence.load() else {
                await persist()
                return
            }
            childName = snapshot.childName
            chores = snapshot.chores
            devices = snapshot.devices
            history = snapshot.history
            await reconcilePolicy()
        } catch {
            errorMessage = "Saved routines couldn’t be loaded. Nothing was restricted automatically."
        }
    }

    func persist() async {
        do {
            try await persistence.save(snapshot)
        } catch {
            errorMessage = "Changes are visible now but couldn’t be saved."
        }
    }

    func reconcilePolicy() async {
        isApplyingPolicy = true
        defer { isApplyingPolicy = false }
        do {
            if case .unlocked = accessState {
                enforcement = try await enforcementService.applyUnlockedPolicy(until: nil)
            } else {
                enforcement = try await enforcementService.applyLockedPolicy()
            }
        } catch {
            errorMessage = "We couldn’t update every device. Essential apps remain available; try again."
        }
    }

    private func update(_ id: UUID, mutation: (inout Chore) -> Void) {
        guard let index = chores.firstIndex(where: { $0.id == id }) else { return }
        mutation(&chores[index])
    }

    private var snapshot: HouseholdSnapshot {
        HouseholdSnapshot(childName: childName, chores: chores, devices: devices, history: Array(history.prefix(100)))
    }

    private func record(_ kind: ActivityEvent.Kind, _ message: String) {
        history.insert(ActivityEvent(kind: kind, message: message), at: 0)
        if history.count > 100 { history.removeLast(history.count - 100) }
    }

    private func persistSoon() {
        Task { await persist() }
    }
}

extension HouseholdStore {
    static var preview: HouseholdStore {
        HouseholdStore(
            role: .parent,
            childName: "Maya",
            chores: [
                Chore(title: "Make your bed", detail: "Blanket straight, pillows up", evidence: .photo, state: .submitted),
                Chore(title: "Feed Pepper", detail: "Food and fresh water", evidence: .checkIn, state: .approved),
                Chore(title: "Practice piano", detail: "20 focused minutes", evidence: .timer)
            ],
            devices: [
                ManagedDevice(name: "Maya’s iPhone", kind: .iPhone, isProtected: true),
                ManagedDevice(name: "Family Room", kind: .appleTV, isProtected: true)
            ]
        )
    }

    static var live: HouseholdStore {
        let fixture = preview
        return HouseholdStore(
            role: fixture.role,
            childName: fixture.childName,
            chores: fixture.chores,
            devices: fixture.devices,
            persistence: LocalHouseholdPersistence()
        )
    }
}
