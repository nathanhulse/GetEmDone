import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: HouseholdStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if store.onboardingStep != .welcome {
                    Button("Back", systemImage: "chevron.left") { store.goBackOnboarding() }
                }
                Spacer()
                Text("\(store.onboardingStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding()

            Spacer()
            VStack(spacing: 24) {
                Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(GEDTheme.accent)
                    .symbolEffect(.pulse, options: .repeating.speed(0.35))
                Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(detail).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if store.onboardingStep == .child {
                    TextField("Child’s first name", text: $store.childName)
                        .textFieldStyle(.roundedBorder).textContentType(.givenName)
                        .frame(maxWidth: 360)
                }
                if store.onboardingStep == .review {
                    GEDCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Essential apps stay available", systemImage: "cross.case.fill")
                            Label("Only Maya’s selected devices", systemImage: "iphone")
                            Label("Parent override is always available", systemImage: "key.fill")
                        }
                    }
                }
            }
            .padding(28)
            Spacer()

            Button(store.onboardingStep == .review ? "Set up my family" : "Continue") {
                if store.onboardingStep == .review {
                    UserDefaults.standard.set(true, forKey: "onboardingComplete")
                }
                store.advanceOnboarding()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.onboardingStep == .child && store.childName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding()
        }
        .background {
            LinearGradient(colors: [GEDTheme.accent.opacity(0.15), GEDTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
        .interactiveDismissDisabled()
    }

    private var symbol: String {
        switch store.onboardingStep {
        case .welcome: "sun.max.fill"
        case .child: "figure.and.child.holdinghands"
        case .protection: "checkmark.shield.fill"
        case .review: "list.clipboard.fill"
        }
    }

    private var title: String {
        switch store.onboardingStep {
        case .welcome: "Calmer mornings start here"
        case .child: "Who are we helping?"
        case .protection: "Pause distractions, not essentials"
        case .review: "You stay in control"
        }
    }

    private var detail: String {
        switch store.onboardingStep {
        case .welcome: "GetEmDone helps responsibilities happen before entertainment—without shutting down communication."
        case .child: "We’ll create a simple daily routine and a separate child experience."
        case .protection: "Choose entertainment apps and websites later. Phone, Messages, Maps, and school tools remain available."
        case .review: "Review every affected device before protection starts. Nothing changes for parent devices."
        }
    }
}
