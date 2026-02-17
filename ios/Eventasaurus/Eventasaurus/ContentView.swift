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
            } else if let user = clerk.user {
                signedInView(user: user)
            } else {
                signedOutView()
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthView(mode: .signIn)
        }
    }

    private func signedInView(user: User) -> some View {
        VStack(spacing: 24) {
            UserButton()

            Text("Welcome, \(user.firstName ?? "User")!")
                .font(.title)

            if let email = user.primaryEmailAddress?.emailAddress {
                Text(email)
                    .foregroundStyle(.secondary)
            }

            Button("Sign Out", role: .destructive) {
                Task {
                    try? await clerk.auth.signOut()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private func signedOutView() -> some View {
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
