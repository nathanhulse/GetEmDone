import XCTest
import GetEmDoneCore
@testable import GetEmDone

@MainActor
final class HouseholdStoreTests: XCTestCase {
    private struct FixedDateProvider: DateProviding {
        var now: Date
    }

    func testSharedScreenTimePolicyRespectsGrantAndSafetyRelease() {
        let now = Date(timeIntervalSince1970: 10_000)
        let policy = SharedScreenTimePolicy(
            policyVersion: 7,
            deviceEnrollmentID: UUID(),
            mode: .locked,
            selectionData: Data([1, 2, 3]),
            grantExpiresAt: now.addingTimeInterval(60),
            safetyReleaseAt: now.addingTimeInterval(3_600)
        )
        XCTAssertFalse(policy.shouldShield(at: now))
        XCTAssertTrue(policy.shouldShield(at: now.addingTimeInterval(61)))
        XCTAssertFalse(policy.shouldShield(at: now.addingTimeInterval(3_600)))
    }
    func testAccessStartsLockedWhenAnyChoreIsWaiting() {
        let store = makeStore(states: [.approved, .waiting])
        XCTAssertEqual(store.accessState, .locked)
        XCTAssertEqual(store.progress, 0.5, accuracy: 0.001)
    }

    func testEmptyRoutineDoesNotSilentlyUnlock() {
        let store = makeStore(states: [])
        XCTAssertEqual(store.accessState, .locked)
    }

    func testSubmittedChoresAwaitApproval() {
        let store = makeStore(states: [.submitted, .submitted])
        XCTAssertEqual(store.accessState, .awaitingApproval)
        XCTAssertTrue(store.canApproveAll)
    }

    func testApprovingSubmittedChoresUnlocksEveryLayer() async {
        let store = makeStore(states: [.submitted, .approved])
        await store.approveSubmitted()
        XCTAssertEqual(store.accessState, .unlocked(until: nil))
        XCTAssertFalse(store.enforcement.phoneAppsShielded)
        XCTAssertFalse(store.enforcement.webDistractionsFiltered)
        XCTAssertFalse(store.enforcement.appleTVPaused)
    }

    func testDailyResetRelocksEveryLayer() async {
        let store = makeStore(states: [.approved, .approved])
        await store.resetDay()
        XCTAssertEqual(store.accessState, .locked)
        XCTAssertTrue(store.enforcement.phoneAppsShielded)
        XCTAssertTrue(store.enforcement.webDistractionsFiltered)
        XCTAssertTrue(store.enforcement.appleTVPaused)
    }

    func testAddingAndRemovingChoreRecordsHistory() {
        let store = makeStore(states: [])
        store.addChore(title: "  Tidy desk  ", detail: "Clear the top", evidence: .photo, activeWeekdays: [2, 4])
        XCTAssertEqual(store.chores.first?.title, "Tidy desk")
        XCTAssertEqual(store.chores.first?.activeWeekdays, [2, 4])
        XCTAssertEqual(store.history.first?.kind, .choreCreated)

        store.removeChores(at: IndexSet(integer: 0))
        XCTAssertTrue(store.chores.isEmpty)
        XCTAssertEqual(store.history.first?.kind, .choreRemoved)
    }

    func testSnapshotRoundTripsThroughPersistence() async throws {
        let persistence = MemoryHouseholdPersistence()
        let first = HouseholdStore(
            role: .parent,
            childName: "Avery",
            chores: [Chore(title: "Read", detail: "Ten pages", evidence: .timer, state: .submitted)],
            devices: [],
            persistence: persistence
        )
        await first.persist()

        let restored = HouseholdStore(role: .parent, childName: "Placeholder", chores: [], devices: [], persistence: persistence)
        await restored.load()
        XCTAssertEqual(restored.childName, "Avery")
        XCTAssertEqual(restored.chores.first?.title, "Read")
        XCTAssertEqual(restored.accessState, .awaitingApproval)
    }

    func testHistoryIsBoundedToOneHundredEvents() async {
        let store = makeStore(states: [.submitted])
        for _ in 0..<120 {
            await store.approveSubmitted()
            await store.resetDay()
            store.role = .child
            store.submit(store.chores[0])
            store.role = .parent
        }
        XCTAssertEqual(store.history.count, 100)
    }

    func testChildCannotApproveOrOverride() {
        let store = HouseholdStore(role: .child, childName: "Test", chores: [Chore(title: "Done", detail: "", evidence: .checkIn, state: .submitted)], devices: [])
        store.approve(store.chores[0])
        store.applyOverride(target: .both)
        XCTAssertEqual(store.chores[0].state, .submitted)
        XCTAssertTrue(store.enforcement.phoneAppsShielded)
        XCTAssertTrue(store.enforcement.appleTVPaused)
    }

    func testAppleTVOverrideDoesNotUnlockPhone() {
        let store = makeStore(states: [.waiting])
        store.applyOverride(target: .appleTV)
        XCTAssertFalse(store.enforcement.appleTVPaused)
        XCTAssertTrue(store.enforcement.phoneAppsShielded)
        XCTAssertEqual(store.accessState, .locked)
    }

    func testRedoStoresParentNote() {
        let store = makeStore(states: [.submitted])
        store.requestRedo(store.chores[0], note: "Please straighten the blanket")
        XCTAssertEqual(store.chores[0].state, .waiting)
        XCTAssertEqual(store.chores[0].parentNote, "Please straighten the blanket")
    }

    func testOnboardingMovesForwardBackAndCompletes() {
        let store = makeStore(states: [])
        store.hasCompletedOnboarding = false
        XCTAssertEqual(store.onboardingStep, .welcome)
        store.advanceOnboarding()
        store.advanceOnboarding()
        store.goBackOnboarding()
        XCTAssertEqual(store.onboardingStep, .child)
        store.advanceOnboarding()
        store.advanceOnboarding()
        store.advanceOnboarding()
        XCTAssertTrue(store.hasCompletedOnboarding)
    }

    func testSuccessfulReconciliationConfirmsProtectionHealth() async {
        let store = makeStore(states: [.waiting])
        await store.reconcilePolicy()
        XCTAssertEqual(store.protectionHealth, .healthy)
    }

    func testPersistenceRejectsOlderRevision() async {
        let persistence = MemoryHouseholdPersistence()
        let newer = HouseholdSnapshot(childName: "New", chores: [], devices: [], history: [])
        let older = HouseholdSnapshot(childName: "Old", chores: [], devices: [], history: [])
        await persistence.save(newer, revision: 2)
        await persistence.save(older, revision: 1)
        let loaded = await persistence.load()
        XCTAssertEqual(loaded?.childName, "New")
    }

    func testLegacyChoreDecodingUsesSafeDefaults() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","title":"Legacy","detail":"","evidence":"checkIn","state":"waiting","activeWeekdays":[1,2,3,4,5,6,7]}
        """
        let chore = try JSONDecoder().decode(Chore.self, from: Data(json.utf8))
        XCTAssertFalse(chore.isArchived)
        XCTAssertEqual(chore.minimumTimerSeconds, 60)
        XCTAssertEqual(chore.evidenceProgress, .none)
        XCTAssertNil(chore.timerStartedAt)
    }

    func testPracticeTimerSurvivesSnapshotRoundTrip() async {
        let persistence = MemoryHouseholdPersistence()
        let start = Date(timeIntervalSince1970: 1_000)
        let chore = Chore(title: "Piano", detail: "", evidence: .timer)
        let first = HouseholdStore(role: .child, childName: "Test", chores: [chore], devices: [], persistence: persistence, dateProvider: FixedDateProvider(now: start))
        first.startPractice(for: chore)
        await first.persist()
        let restored = HouseholdStore(role: .child, childName: "Test", chores: [], devices: [], persistence: persistence, dateProvider: FixedDateProvider(now: start.addingTimeInterval(90)))
        await restored.load()
        XCTAssertEqual(restored.elapsedPractice(for: restored.chores[0]), 90)
    }

    func testTemporaryOverrideExpiresAndRelocks() async {
        let start = Date(timeIntervalSince1970: 2_000)
        let persistence = MemoryHouseholdPersistence()
        let active = HouseholdStore(role: .parent, childName: "Test", chores: [Chore(title: "Bed", detail: "", evidence: .checkIn)], devices: [], persistence: persistence, dateProvider: FixedDateProvider(now: start))
        active.applyOverride(target: .appleTV, duration: 60)
        await active.reconcilePolicy()
        XCTAssertFalse(active.enforcement.appleTVPaused)
        await active.persist()
        let expired = HouseholdStore(role: .parent, childName: "Test", chores: [], devices: [], persistence: persistence, dateProvider: FixedDateProvider(now: start.addingTimeInterval(61)))
        await expired.load()
        XCTAssertTrue(expired.enforcement.appleTVPaused)
        XCTAssertTrue(expired.temporaryOverrides.isEmpty)
    }

    func testDuplicateAndIllegalReviewCommandsAreNoOps() {
        let submitted = Chore(title: "Bed", detail: "", evidence: .checkIn, state: .submitted)
        let store = HouseholdStore(role: .parent, childName: "Test", chores: [submitted], devices: [])
        store.approve(submitted)
        let eventCount = store.history.count
        store.approve(submitted)
        store.requestRedo(submitted)
        XCTAssertEqual(store.history.count, eventCount)
        XCTAssertEqual(store.chores[0].state, .approved)
    }

    func testDuplicateTimerStartAndStopAreNoOps() {
        let start = Date(timeIntervalSince1970: 3_000)
        let chore = Chore(title: "Piano", detail: "", evidence: .timer)
        let store = HouseholdStore(role: .child, childName: "Test", chores: [chore], devices: [], dateProvider: FixedDateProvider(now: start))
        store.startPractice(for: chore)
        let firstStart = store.chores[0].timerStartedAt
        store.startPractice(for: chore)
        XCTAssertEqual(store.chores[0].timerStartedAt, firstStart)
        store.stopPractice(for: chore)
        let progress = store.chores[0].evidenceProgress
        store.stopPractice(for: chore)
        XCTAssertEqual(store.chores[0].evidenceProgress, progress)
    }

    func testSimulatorScreenTimeControllerNeverClaimsRealProtection() async {
        let controller = SimulatedScreenTimeController()
        let status = await controller.authorizationStatus()
        XCTAssertEqual(status, .simulated)
        let locked = await controller.applyLockedPolicy()
        XCTAssertEqual(locked.capability, .simulated)
        XCTAssertTrue(locked.appsShielded)
        let unlocked = await controller.applyUnlockedPolicy()
        XCTAssertEqual(unlocked.capability, .simulated)
        XCTAssertFalse(unlocked.appsShielded)
    }

    func testWeekdayScheduleSelectsOnlyActiveChores() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        let store = HouseholdStore(role: .parent, childName: "Test", chores: [
            Chore(title: "Weekday", detail: "", evidence: .checkIn, activeWeekdays: Set(2...6)),
            Chore(title: "Weekend", detail: "", evidence: .checkIn, activeWeekdays: [1, 7]),
            Chore(title: "Archived", detail: "", evidence: .checkIn, isArchived: true)
        ], devices: [])
        XCTAssertEqual(store.activeChores(on: monday, calendar: calendar).map(\.title), ["Weekday"])
    }

    func testEditingChorePreservesIdentityAndRecordsEvent() {
        let store = makeStore(states: [.waiting])
        var chore = store.chores[0]
        chore.title = "Updated"
        chore.dueMinutes = 510
        store.updateChore(chore)
        XCTAssertEqual(store.chores[0].id, chore.id)
        XCTAssertEqual(store.chores[0].dueMinutes, 510)
        XCTAssertEqual(store.history.first?.kind, .choreEdited)
    }

    func testPhotoChoreCannotSubmitWithoutEvidence() {
        let chore = Chore(title: "Bed", detail: "", evidence: .photo)
        let store = HouseholdStore(role: .child, childName: "Test", chores: [chore], devices: [])
        store.submit(chore)
        XCTAssertEqual(store.chores[0].state, .waiting)
        store.attachPhoto(to: chore)
        store.submit(store.chores[0])
        XCTAssertEqual(store.chores[0].state, .submitted)
    }

    func testTimerChoreRequiresMinimumDuration() {
        let chore = Chore(title: "Piano", detail: "", evidence: .timer, minimumTimerSeconds: 60)
        let store = HouseholdStore(role: .child, childName: "Test", chores: [chore], devices: [])
        store.recordPractice(seconds: 30, for: chore)
        store.submit(store.chores[0])
        XCTAssertEqual(store.chores[0].state, .waiting)
        store.recordPractice(seconds: 60, for: chore)
        store.submit(store.chores[0])
        XCTAssertEqual(store.chores[0].state, .submitted)
    }

    private func makeStore(states: [ChoreState]) -> HouseholdStore {
        HouseholdStore(
            role: .parent,
            childName: "Test",
            chores: states.enumerated().map { index, state in
                Chore(title: "Chore \(index)", detail: "Detail", evidence: .checkIn, state: state)
            },
            devices: []
        )
    }
}
