import SwiftUI
import ClerkKit
import ClerkKitUI

struct ProfileView: View {
    @Environment(Clerk.self) private var clerk
    @State private var profile: UserProfile?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isLoading {
                    ProgressView()
                } else if let profile {
                    profileContent(profile)
                } else {
                    clerkFallback
                }

                Spacer()

                Button("Sign Out", role: .destructive) {
                    Task { try? await clerk.auth.signOut() }
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 32)
            }
            .padding()
            .navigationTitle("Profile")
            .task { await loadProfile() }
        }
    }

    private func profileContent(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            // Avatar
            if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }

            Text(profile.name)
                .font(.title2.bold())

            if let username = profile.username {
                Text("@\(username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(profile.email)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    // Fallback: show Clerk user info if API call fails
    private var clerkFallback: some View {
        VStack(spacing: 12) {
            UserButton()

            if let user = clerk.user {
                Text("Welcome, \(user.firstName ?? "User")!")
                    .font(.title2)
            }
        }
    }

    private func loadProfile() async {
        do {
            profile = try await APIClient.shared.fetchProfile()
        } catch {
            // Profile fetch failed — will show Clerk fallback
        }
        isLoading = false
    }
}
