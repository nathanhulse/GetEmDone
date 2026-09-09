import SwiftUI

@main
struct GetEmDoneApp: App {
    @StateObject private var store = HouseholdStore.live

    var body: some Scene {
        WindowGroup {
            AppShell(store: store)
                .task { await store.load() }
        }
    }
}
