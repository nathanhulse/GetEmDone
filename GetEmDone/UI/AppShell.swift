import SwiftUI

struct AppShell: View {
    @ObservedObject var store: HouseholdStore

    var body: some View {
        TabView {
            NavigationStack { TodayView(store: store) }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }

            NavigationStack { DevicesView(store: store) }
                .tabItem { Label("Devices", systemImage: "wifi.router") }

            NavigationStack { HistoryView(store: store) }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            NavigationStack { SettingsView(store: store) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(GEDTheme.accent)
    }
}
