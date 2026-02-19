import SwiftUI
import ClerkKit
import ClerkKitUI

struct ContentView: View {
    @Environment(Clerk.self) private var clerk
    @State private var showAuth = false

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
    }

    private var mainTabView: some View {
        TabView {
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "magnifyingglass")
                }

            MoviesView()
                .tabItem {
                    Label("Movies", systemImage: "film")
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
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("Eventasaurus")
                .font(.largeTitle.bold())

            Text("Sign in to see events near you")
                .foregroundStyle(.secondary)

            Button("Sign In") {
                showAuth = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

#Preview("Signed Out") {
    ContentView()
        .environment(Clerk.preview { preview in
            preview.isSignedIn = false
        })
}
