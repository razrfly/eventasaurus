import SwiftUI
import ClerkKit

@main
struct EventasaurusApp: App {
    #if DEBUG
    private static let clerkKey = "pk_test_cmFyZS1tdXNrb3gtODkuY2xlcmsuYWNjb3VudHMuZGV2JA"
    #else
    private static let clerkKey = "pk_live_Y2xlcmsud29tYmllLmNvbSQ"
    #endif

    init() {
        Clerk.configure(publishableKey: Self.clerkKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(Clerk.shared)
        }
    }
}
