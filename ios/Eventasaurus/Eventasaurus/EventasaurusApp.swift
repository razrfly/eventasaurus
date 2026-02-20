import SwiftUI
import ClerkKit

@main
struct EventasaurusApp: App {
    init() {
        Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(Clerk.shared)
        }
    }
}
