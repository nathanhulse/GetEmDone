import SwiftUI

struct AppShell: View {
    @ObservedObject var store: HouseholdStore

    var body: some View {
        TabView {
            NavigationStack { TodayView(store: store) }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }

            if store.role == .parent {
                NavigationStack { DevicesView(store: store) }
                    .tabItem { Label("Access", systemImage: "checkmark.shield") }
            } else {
                NavigationStack { ChildStatusView(store: store) }
                    .tabItem { Label("Status", systemImage: "lock.shield") }
            }

            NavigationStack { HistoryView(store: store) }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            if store.role == .parent {
                NavigationStack { SettingsView(store: store) }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
        .tint(GEDTheme.accent(for: store.role))
        .animation(.snappy, value: store.role)
    }
}
