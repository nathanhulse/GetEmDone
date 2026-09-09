import SwiftUI

@main
struct GetEmDoneApp: App {
    @StateObject private var store = HouseholdStore.preview

    var body: some Scene {
        WindowGroup {
            AppShell(store: store)
        }
    }
}
