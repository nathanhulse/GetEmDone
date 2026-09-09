import XCTest
@testable import GetEmDone

@MainActor
final class HouseholdStoreTests: XCTestCase {
    func testAccessStartsLockedWhenAnyChoreIsWaiting() {
        let store = makeStore(states: [.approved, .waiting])
        XCTAssertEqual(store.accessState, .locked)
        XCTAssertEqual(store.progress, 0.5, accuracy: 0.001)
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

