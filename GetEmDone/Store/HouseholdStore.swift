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
    @Published var protectionHealth: ProtectionHealth = .unknown
    @Published var onboardingStep: OnboardingStep = .welcome
    @Published var hasCompletedOnboarding: Bool
    @Published var temporaryOverrides: [TemporaryOverride]
    @Published private(set) var evidenceUploadStates: [UUID: EvidenceUploadState] = [:]

    private let enforcementService: any EnforcementService
    private let persistence: any HouseholdPersistence
    private var persistenceRevision: UInt64 = 0
    private let dateProvider: any DateProviding
    private let evidenceUploader: any EvidenceUploading
    private let imageSanitizer: any EvidenceImageSanitizing
    private struct PendingEvidence {
        let evidenceID: UUID
        let data: Data
    }
    private var pendingEvidence: [UUID: PendingEvidence] = [:]

    init(
        role: HouseholdRole,
        childName: String,
        chores: [Chore],
        devices: [ManagedDevice],
        history: [ActivityEvent] = [],
        enforcementService: any EnforcementService = DemoEnforcementService(),
        persistence: any HouseholdPersistence = MemoryHouseholdPersistence(),
        dateProvider: any DateProviding = SystemDateProvider(),
        evidenceUploader: any EvidenceUploading = EvidenceAPIClient(configuration: nil),
        imageSanitizer: any EvidenceImageSanitizing = MetadataStrippingImageSanitizer()
    ) {
        self.role = role
        self.childName = childName
        self.chores = chores
        self.devices = devices
        self.history = history
        self.enforcementService = enforcementService
        self.persistence = persistence
        self.hasCompletedOnboarding = role == .parent && !chores.isEmpty
        self.temporaryOverrides = []
        self.dateProvider = dateProvider
        self.evidenceUploader = evidenceUploader
        self.imageSanitizer = imageSanitizer
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
        guard role == .child else { return }
        guard let current = chores.first(where: { $0.id == chore.id }), current.state == .waiting, current.canSubmit else { return }
        update(chore.id) { $0.state = .submitted }
        record(.submitted, "\(chore.title) was submitted")
        persistSoon()
    }

    func attachPhoto(to chore: Chore) {
        guard role == .child,
              let current = chores.first(where: { $0.id == chore.id }),
              current.state == .waiting,
              current.evidence == .photo,
              current.evidenceProgress != .photoReady else { return }
        update(chore.id) { $0.evidenceProgress = .photoReady }
        persistSoon()
    }

    func evidenceUploadState(for chore: Chore) -> EvidenceUploadState {
        evidenceUploadStates[chore.id] ?? .idle
    }

    func canRetryPhotoUpload(for chore: Chore) -> Bool {
        pendingEvidence[chore.id] != nil
    }

    func uploadPhoto(_ originalData: Data, for chore: Chore) async {
        guard role == .child,
              let current = chores.first(where: { $0.id == chore.id }),
              current.state == .waiting,
              current.evidence == .photo else { return }
        evidenceUploadStates[chore.id] = .preparing
        do {
            let sanitized = try imageSanitizer.sanitizedJPEG(from: originalData)
            pendingEvidence[chore.id] = PendingEvidence(evidenceID: UUID(), data: sanitized)
            await uploadPendingPhoto(for: current)
        } catch {
            evidenceUploadStates[chore.id] = .failed(message: userFacingEvidenceError(error))
        }
    }

    func retryPhotoUpload(for chore: Chore) async {
        guard let current = chores.first(where: { $0.id == chore.id }),
              pendingEvidence[chore.id] != nil else { return }
        await uploadPendingPhoto(for: current)
    }

    func reportPhotoSelectionFailure(for chore: Chore) {
        guard role == .child,
              chores.first(where: { $0.id == chore.id })?.state == .waiting else { return }
        evidenceUploadStates[chore.id] = .failed(message: EvidenceUploadError.invalidImage.localizedDescription)
    }

    func removePendingPhoto(for chore: Chore) {
        guard chores.first(where: { $0.id == chore.id })?.state == .waiting else { return }
        pendingEvidence[chore.id] = nil
        evidenceUploadStates[chore.id] = .idle
        update(chore.id) { $0.evidenceProgress = .none }
        persistSoon()
    }

    func recordPractice(seconds: Int, for chore: Chore) {
        guard role == .child, seconds > 0,
              let current = chores.first(where: { $0.id == chore.id }),
              current.state == .waiting,
              current.evidence == .timer else { return }
        update(chore.id) { $0.evidenceProgress = .timer(seconds: seconds) }
        persistSoon()
    }

    func startPractice(for chore: Chore) {
        guard role == .child,
              let current = chores.first(where: { $0.id == chore.id }),
              current.state == .waiting,
              current.evidence == .timer,
              current.timerStartedAt == nil else { return }
        update(chore.id) { current in
            current.timerStartedAt = dateProvider.now
        }
        persistSoon()
    }

    func stopPractice(for chore: Chore) {
        guard role == .child, let current = chores.first(where: { $0.id == chore.id }), let started = current.timerStartedAt else { return }
        let elapsed = max(0, Int(dateProvider.now.timeIntervalSince(started)))
        update(chore.id) {
            let prior: Int
            if case .timer(let seconds) = $0.evidenceProgress { prior = seconds } else { prior = 0 }
            $0.evidenceProgress = .timer(seconds: prior + elapsed)
            $0.timerStartedAt = nil
        }
        persistSoon()
    }

    func elapsedPractice(for chore: Chore, at date: Date? = nil) -> Int {
        guard let current = chores.first(where: { $0.id == chore.id }) else { return 0 }
        let accumulated: Int
        if case .timer(let seconds) = current.evidenceProgress { accumulated = seconds } else { accumulated = 0 }
        guard let started = current.timerStartedAt else { return accumulated }
        return accumulated + max(0, Int((date ?? dateProvider.now).timeIntervalSince(started)))
    }

    func approve(_ chore: Chore) {
        guard role == .parent,
              chores.first(where: { $0.id == chore.id })?.state == .submitted else { return }
        update(chore.id) { $0.state = .approved }
        record(.approved, "\(chore.title) was approved")
        persistSoon()
    }

    func requestRedo(_ chore: Chore, note: String? = nil) {
        guard role == .parent,
              chores.first(where: { $0.id == chore.id })?.state == .submitted else { return }
        update(chore.id) {
            $0.state = .waiting
            $0.parentNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
        guard !cleaned.title.isEmpty, !cleaned.activeWeekdays.isEmpty, cleaned != chores[index] else { return }
        chores[index] = cleaned
        record(.choreEdited, "\(cleaned.title) was updated")
        persistSoon()
    }

    func setArchived(_ archived: Bool, chore: Chore) {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }), chores[index].isArchived != archived else { return }
        chores[index].isArchived = archived
        record(.choreEdited, "\(chore.title) was \(archived ? "archived" : "restored")")
        persistSoon()
    }

    func activeChores(on date: Date? = nil, calendar: Calendar = .current) -> [Chore] {
        let weekday = calendar.component(.weekday, from: date ?? dateProvider.now)
        return chores.filter { !$0.isArchived && $0.activeWeekdays.contains(weekday) }
    }

    func approveSubmitted() async {
        guard role == .parent else { return }
        guard chores.contains(where: { $0.state == .submitted }) else { return }
        for index in chores.indices where chores[index].state == .submitted {
            record(.approved, "\(chores[index].title) was approved")
            chores[index].state = .approved
        }
        await persist()
        await reconcilePolicy()
    }

    func unlockForToday() async {
        guard role == .parent else { return }
        for index in chores.indices { chores[index].state = .approved }
        record(.override, "Parent unlocked entertainment for today")
        await persist()
        await reconcilePolicy()
    }

    func applyOverride(target: OverrideTarget, duration: TimeInterval = 30 * 60) {
        guard role == .parent else { return }
        let now = dateProvider.now
        temporaryOverrides.append(TemporaryOverride(target: target, startsAt: now, expiresAt: now.addingTimeInterval(max(1, duration))))
        enforcement = desiredPolicy(at: now)
        record(.override, "Parent temporarily unlocked \(target.title)")
        persistSoon()
        Task { await reconcilePolicy() }
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
            temporaryOverrides = snapshot.temporaryOverrides
            await reconcilePolicy()
        } catch {
            errorMessage = "Saved routines couldn’t be loaded. Nothing was restricted automatically."
        }
    }

    func persist() async {
        persistenceRevision &+= 1
        let revision = persistenceRevision
        let value = snapshot
        do {
            try await persistence.save(value, revision: revision)
        } catch {
            errorMessage = "Changes are visible now but couldn’t be saved."
        }
    }

    func reconcilePolicy() async {
        isApplyingPolicy = true
        protectionHealth = .applying
        defer { isApplyingPolicy = false }
        do {
            let now = dateProvider.now
            temporaryOverrides.removeAll { $0.expiresAt <= now }
            enforcement = try await enforcementService.applyPolicy(desiredPolicy(at: now))
            protectionHealth = .healthy
        } catch {
            errorMessage = "We couldn’t update every device. Essential apps remain available; try again."
            protectionHealth = .degraded(message: "One or more protection layers could not be confirmed.")
        }
    }

    func advanceOnboarding() {
        guard let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) else {
            hasCompletedOnboarding = true
            return
        }
        onboardingStep = next
    }

    func goBackOnboarding() {
        onboardingStep = OnboardingStep(rawValue: max(0, onboardingStep.rawValue - 1)) ?? .welcome
    }

    private func update(_ id: UUID, mutation: (inout Chore) -> Void) {
        guard let index = chores.firstIndex(where: { $0.id == id }) else { return }
        mutation(&chores[index])
    }

    private func uploadPendingPhoto(for chore: Chore) async {
        guard let pending = pendingEvidence[chore.id] else { return }
        evidenceUploadStates[chore.id] = .uploading
        do {
            let receipt = try await evidenceUploader.uploadJPEG(
                pending.data,
                evidenceID: pending.evidenceID,
                choreID: chore.id,
                expiresAt: dateProvider.now.addingTimeInterval(24 * 60 * 60)
            )
            pendingEvidence[chore.id] = nil
            evidenceUploadStates[chore.id] = .uploaded(evidenceID: receipt.evidenceID)
            attachPhoto(to: chore)
        } catch {
            evidenceUploadStates[chore.id] = .failed(message: userFacingEvidenceError(error))
        }
    }

    private func userFacingEvidenceError(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "The photo couldn't be uploaded. Check your connection and try again."
    }

    private var snapshot: HouseholdSnapshot {
        HouseholdSnapshot(childName: childName, chores: chores, devices: devices, history: Array(history.prefix(100)), temporaryOverrides: temporaryOverrides)
    }

    private func desiredPolicy(at date: Date) -> EnforcementSnapshot {
        let baseLocked: Bool
        if case .unlocked = accessState { baseLocked = false } else { baseLocked = true }
        var desired = EnforcementSnapshot(phoneAppsShielded: baseLocked, webDistractionsFiltered: baseLocked, appleTVPaused: baseLocked)
        for grant in temporaryOverrides where grant.isActive(at: date) {
            switch grant.target {
            case .phone:
                desired.phoneAppsShielded = false
                desired.webDistractionsFiltered = false
            case .appleTV:
                desired.appleTVPaused = false
            case .both:
                desired = .init(phoneAppsShielded: false, webDistractionsFiltered: false, appleTVPaused: false)
            }
        }
        return desired
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
        let store = HouseholdStore(
            role: fixture.role,
            childName: fixture.childName,
            chores: fixture.chores,
            devices: fixture.devices,
            persistence: LocalHouseholdPersistence(),
            evidenceUploader: EvidenceAPIClient(configuration: .development)
        )
        store.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "onboardingComplete")
        return store
    }
}
