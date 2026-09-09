import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private var standard: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: .systemBackground,
            icon: UIImage(systemName: "checkmark.circle"),
            title: .init(text: "Responsibilities first", color: .label),
            subtitle: .init(text: "Finish today’s responsibilities, then ask a parent to review them.", color: .secondaryLabel),
            primaryButtonLabel: .init(text: "Ask Parent", color: .white),
            primaryButtonBackgroundColor: .systemIndigo,
            secondaryButtonLabel: .init(text: "Not now", color: .systemIndigo)
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration { standard }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { standard }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { standard }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { standard }
}
