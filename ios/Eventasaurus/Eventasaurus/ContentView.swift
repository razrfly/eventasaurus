import SwiftUI
import ClerkKit
import ClerkKitUI

struct ContentView: View {
    @Environment(Clerk.self) private var clerk
    @State private var showAuth = false
    @Binding var deepLinkSlug: String?

    var body: some View {
        Group {
            if !clerk.isLoaded {
                ProgressView("Loading...")
            } else if clerk.user != nil {
                mainTabView
            } else {
                signedOutView
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthView(mode: .signIn)
        }
        .sheet(isPresented: Binding(
            get: { deepLinkSlug != nil },
            set: { if !$0 { deepLinkSlug = nil } }
        )) {
            if let slug = deepLinkSlug {
                NavigationStack {
                    EventDetailView(slug: slug)
                }
            }
        }
    }

    private var mainTabView: some View {
        TabView {
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "magnifyingglass")
                }

            MyEventsView()
                .tabItem {
                    Label("My Events", systemImage: "calendar")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
        }
    }

    private var signedOutView: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Wombie")
                .font(DS.Typography.display)

            Text("Sign in to see events near you")
                .foregroundStyle(.secondary)

            Button("Sign In") {
                showAuth = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(DS.Spacing.xl)
    }
}

#Preview("Signed Out") {
    ContentView(deepLinkSlug: .constant(nil))
        .environment(Clerk.preview { preview in
            preview.isSignedIn = false
        })
}
