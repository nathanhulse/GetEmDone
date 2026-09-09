import SwiftUI

struct AppShell: View {
    @ObservedObject var store: HouseholdStore

    var body: some View {
        TabView {
            NavigationStack { TodayView(store: store) }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }

            if store.role == .parent {
                NavigationStack { ReviewQueueView(store: store) }
                    .tabItem { Label("Review", systemImage: "tray.full") }
                    .badge(store.chores.filter { $0.state == .submitted }.count)

                NavigationStack { RoutineView(store: store) }
                    .tabItem { Label("Routine", systemImage: "checklist") }

                NavigationStack { DevicesView(store: store) }
                    .tabItem { Label("Access", systemImage: "checkmark.shield") }
            } else {
                NavigationStack { ChildStatusView(store: store) }
                    .tabItem { Label("Status", systemImage: "lock.shield") }
            }

            if store.role == .child {
                NavigationStack { HistoryView(store: store) }
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            }

        }
        .tint(GEDTheme.accent(for: store.role))
        .animation(.snappy, value: store.role)
    }
}
