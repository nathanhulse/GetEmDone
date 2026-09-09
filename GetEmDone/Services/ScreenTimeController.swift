import Foundation

enum ScreenTimeCapability: String, Codable, Sendable {
    case simulated
    case available
    case unauthorized
    case unavailable
    case failed
}

struct ScreenTimeReport: Equatable, Sendable {
    var capability: ScreenTimeCapability
    var appsShielded: Bool
    var webDomainsShielded: Bool
    var message: String
}

protocol ScreenTimeControlling: Sendable {
    func authorizationStatus() async -> ScreenTimeCapability
    func requestAuthorization() async throws -> ScreenTimeCapability
    func applyLockedPolicy() async throws -> ScreenTimeReport
    func applyUnlockedPolicy() async throws -> ScreenTimeReport
}

actor SimulatedScreenTimeController: ScreenTimeControlling {
    private var locked = true

    func authorizationStatus() -> ScreenTimeCapability { .simulated }
    func requestAuthorization() -> ScreenTimeCapability { .simulated }

    func applyLockedPolicy() -> ScreenTimeReport {
        locked = true
        return report
    }

    func applyUnlockedPolicy() -> ScreenTimeReport {
        locked = false
        return report
    }

    private var report: ScreenTimeReport {
        ScreenTimeReport(
            capability: .simulated,
            appsShielded: locked,
            webDomainsShielded: locked,
            message: "Simulator preview only—no system restrictions are active."
        )
    }
}

enum ScreenTimeComposition {
    static func make() -> any ScreenTimeControlling {
#if targetEnvironment(simulator)
        SimulatedScreenTimeController()
#else
        SystemScreenTimeController()
#endif
    }
}

#if canImport(FamilyControls) && canImport(ManagedSettings) && canImport(DeviceActivity)
import DeviceActivity
@preconcurrency import FamilyControls
import ManagedSettings

@MainActor
final class SystemScreenTimeController: ScreenTimeControlling, @unchecked Sendable {
    static let storeName = ManagedSettingsStore.Name("com.getemdone.chore-lock")
    static let activityName = DeviceActivityName("com.getemdone.daily-chore-window")

    private let authorizationCenter = AuthorizationCenter.shared
    private let store = ManagedSettingsStore(named: storeName)
    private let activityCenter = DeviceActivityCenter()
    private var selection = FamilyActivitySelection()

    func authorizationStatus() -> ScreenTimeCapability {
        switch authorizationCenter.authorizationStatus {
        case .approved: .available
        case .notDetermined, .denied: .unauthorized
        default: .unavailable
        }
    }

    func requestAuthorization() async throws -> ScreenTimeCapability {
        try await authorizationCenter.requestAuthorization(for: .child)
        return authorizationStatus()
    }

    func updateSelection(_ selection: FamilyActivitySelection) {
        self.selection = selection
    }

    func applyLockedPolicy() -> ScreenTimeReport {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        return ScreenTimeReport(
            capability: authorizationStatus(),
            appsShielded: !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty,
            webDomainsShielded: !selection.webDomainTokens.isEmpty,
            message: "Selected distractions are shielded by Screen Time."
        )
    }

    func applyUnlockedPolicy() -> ScreenTimeReport {
        store.clearAllSettings()
        return ScreenTimeReport(
            capability: authorizationStatus(),
            appsShielded: false,
            webDomainsShielded: false,
            message: "GetEmDone’s named Screen Time store is clear."
        )
    }

    func replaceDailySchedule(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) throws {
        activityCenter.stopMonitoring([Self.activityName])
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: startHour, minute: startMinute),
            intervalEnd: DateComponents(hour: endHour, minute: endMinute),
            repeats: true
        )
        try activityCenter.startMonitoring(Self.activityName, during: schedule)
    }
}
#else
final class SystemScreenTimeController: ScreenTimeControlling, @unchecked Sendable {
    func authorizationStatus() async -> ScreenTimeCapability { .unavailable }
    func requestAuthorization() async throws -> ScreenTimeCapability { .unavailable }
    func applyLockedPolicy() async throws -> ScreenTimeReport { unavailable }
    func applyUnlockedPolicy() async throws -> ScreenTimeReport { unavailable }

    private var unavailable: ScreenTimeReport {
        ScreenTimeReport(capability: .unavailable, appsShielded: false, webDomainsShielded: false, message: "Screen Time frameworks are unavailable.")
    }
}
#endif
