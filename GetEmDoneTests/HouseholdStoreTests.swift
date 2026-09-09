import XCTest
@testable import GetEmDone

@MainActor
final class HouseholdStoreTests: XCTestCase {
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
