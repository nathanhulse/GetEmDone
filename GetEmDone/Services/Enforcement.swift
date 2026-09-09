import Foundation

struct EnforcementSnapshot: Equatable {
    var phoneAppsShielded: Bool
    var webDistractionsFiltered: Bool
    var appleTVPaused: Bool
}

protocol EnforcementService: Sendable {
    func applyLockedPolicy() async throws -> EnforcementSnapshot
    func applyUnlockedPolicy(until: Date?) async throws -> EnforcementSnapshot
    func applyPolicy(_ desired: EnforcementSnapshot) async throws -> EnforcementSnapshot
}

actor DemoEnforcementService: EnforcementService {
    private var snapshot = EnforcementSnapshot(
        phoneAppsShielded: true,
        webDistractionsFiltered: true,
        appleTVPaused: true
    )

    func applyLockedPolicy() async throws -> EnforcementSnapshot {
        snapshot = .init(phoneAppsShielded: true, webDistractionsFiltered: true, appleTVPaused: true)
        return snapshot
    }

    func applyUnlockedPolicy(until: Date?) async throws -> EnforcementSnapshot {
        snapshot = .init(phoneAppsShielded: false, webDistractionsFiltered: false, appleTVPaused: false)
        return snapshot
    }

    func applyPolicy(_ desired: EnforcementSnapshot) async throws -> EnforcementSnapshot {
        snapshot = desired
        return snapshot
    }
}
