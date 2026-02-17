import SwiftUI
import ClerkKit

@main
struct EventasaurusApp: App {
    init() {
        Clerk.configure(publishableKey: "pk_test_cmFyZS1tdXNrb3gtODkuY2xlcmsuYWNjb3VudHMuZGV2JA")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(Clerk.shared)
        }
    }
}
