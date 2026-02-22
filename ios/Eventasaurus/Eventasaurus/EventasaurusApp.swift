import SwiftUI
import ClerkKit

@main
struct EventasaurusApp: App {
    @State private var deepLinkSlug: String?

    init() {
        Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkSlug: $deepLinkSlug)
                .environment(Clerk.shared)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let host = url.host(),
              host == "wombie.com" || host == "www.wombie.com" else { return }

        let path = url.pathComponents
        // Match /events/{slug} or /activities/{slug}
        if path.count >= 3,
           (path[1] == "events" || path[1] == "activities") {
            deepLinkSlug = path[2]
        }
    }
}
