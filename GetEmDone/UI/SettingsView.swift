import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: HouseholdStore
    @State private var safetyFilter = true
    @State private var requireApproval = true
    @State private var dailyReset = true

    var body: some View {
        Form {
            Section("Daily routine") {
                Toggle("Reset every morning", isOn: $dailyReset)
                Toggle("Require parent approval", isOn: $requireApproval)
                Button("Reset today now") { Task { await store.resetDay() } }
            }
            Section("Protection") {
                Toggle("Always-on safety filter", isOn: $safetyFilter)
                NavigationLink("Choose entertainment apps") { CapabilityPlaceholder(title: "App selection", detail: "Apple’s privacy-preserving Family Activity Picker will appear here once the distribution entitlement is enabled.") }
                NavigationLink("Website categories") { CapabilityPlaceholder(title: "Web filters", detail: "Safety and chore-time filters are configured independently so approval never removes basic protection.") }
            }
            Section("Safety") {
                Label("Phone, Messages, Maps and school tools stay available", systemImage: "cross.case.fill")
                Label("Parent recovery code enabled", systemImage: "key.fill")
            }
        }
        .navigationTitle("Settings")
    }
}

private struct CapabilityPlaceholder: View {
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer.fill", description: Text(detail))
            .navigationTitle(title)
    }
}
