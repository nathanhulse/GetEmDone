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
            store.submit(store.chores[0])
        }
        XCTAssertEqual(store.history.count, 100)
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
