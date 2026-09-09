import DeviceActivity
import Foundation
import GetEmDoneCore
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let settings = ManagedSettingsStore(named: .init("com.getemdone.chore-lock"))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        reconcile()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        reconcile()
    }

    private func reconcile() {
        guard let policy = try? SharedPolicyStore.appGroup().load() else {
            return // Never broaden shields when shared state is missing or invalid.
        }
        if !policy.shouldShield(at: Date()) {
            settings.clearAllSettings()
        }
        // Opaque FamilyActivitySelection decoding and token application stays in the
        // containing app until production entitlement/device validation is complete.
    }
}
