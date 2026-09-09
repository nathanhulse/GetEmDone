import Foundation
import Combine

@MainActor
final class HouseholdStore: ObservableObject {
    @Published var role: HouseholdRole
    @Published var childName: String
    @Published var chores: [Chore]
    @Published var devices: [ManagedDevice]
    @Published var enforcement: EnforcementSnapshot
    @Published var isApplyingPolicy = false
    @Published var errorMessage: String?

    private let enforcementService: any EnforcementService

    init(
        role: HouseholdRole,
        childName: String,
        chores: [Chore],
        devices: [ManagedDevice],
        enforcementService: any EnforcementService = DemoEnforcementService()
    ) {
        self.role = role
        self.childName = childName
        self.chores = chores
        self.devices = devices
        self.enforcementService = enforcementService
        self.enforcement = .init(phoneAppsShielded: true, webDistractionsFiltered: true, appleTVPaused: true)
    }

    var accessState: AccessState {
        if chores.allSatisfy({ $0.state == .approved }) { return .unlocked(until: nil) }
        if chores.allSatisfy({ $0.state != .waiting }) { return .awaitingApproval }
        return .locked
    }

    var completedCount: Int { chores.filter { $0.state != .waiting }.count }
    var progress: Double { chores.isEmpty ? 0 : Double(completedCount) / Double(chores.count) }
    var canApproveAll: Bool { chores.contains { $0.state == .submitted } }

    func submit(_ chore: Chore) {
        update(chore.id) { $0.state = .submitted }
    }

    func approve(_ chore: Chore) {
        update(chore.id) { $0.state = .approved }
    }

    func requestRedo(_ chore: Chore) {
        update(chore.id) { $0.state = .waiting }
    }

    func approveSubmitted() async {
        for index in chores.indices where chores[index].state == .submitted {
            chores[index].state = .approved
        }
        await reconcilePolicy()
    }

    func unlockForToday() async {
        for index in chores.indices { chores[index].state = .approved }
        await reconcilePolicy()
    }

    func resetDay() async {
        for index in chores.indices { chores[index].state = .waiting }
        await reconcilePolicy()
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
}
