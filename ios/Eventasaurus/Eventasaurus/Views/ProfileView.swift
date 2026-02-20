import SwiftUI
import ClerkKit
import ClerkKitUI

struct ProfileView: View {
    @Environment(Clerk.self) private var clerk
    @State private var profile: UserProfile?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xxxl) {
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
                .padding(.bottom, DS.Spacing.jumbo)
            }
            .padding(DS.Spacing.xl)
            .navigationTitle("Profile")
            .task { await loadProfile() }
        }
    }

    private func profileContent(_ profile: UserProfile) -> some View {
        VStack(spacing: DS.Spacing.xl) {
            // Avatar
            if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                CachedImage(
                    url: url,
                    height: DS.ImageSize.avatarLarge,
                    cornerRadius: 0,
                    placeholderIcon: "person.fill",
                    contentMode: .fill
                )
                .frame(width: DS.ImageSize.avatarLarge)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }

            Text(profile.name)
                .font(DS.Typography.title)

            if let username = profile.username {
                Text("@\(username)")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }

            Text(profile.email)
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(DS.Typography.prose)
                    .multilineTextAlignment(.center)
                    .padding(.top, DS.Spacing.xs)
            }
        }
    }

    // Fallback: show Clerk user info if API call fails
    private var clerkFallback: some View {
        VStack(spacing: DS.Spacing.lg) {
            UserButton()

            if let user = clerk.user {
                Text("Welcome, \(user.firstName ?? "User")!")
                    .font(DS.Typography.title)
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
