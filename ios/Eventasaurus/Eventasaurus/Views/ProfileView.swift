import SwiftUI
import ClerkKit
import ClerkKitUI

struct ProfileView: View {
    @Environment(Clerk.self) private var clerk
    @State private var profile: GQLUser?
    @State private var isLoading = true
    @State private var showSignOutError = false
    @State private var signOutErrorMessage = ""

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

                VStack(spacing: DS.Spacing.lg) {
                    #if DEBUG
                    readOnlyEnvironmentIndicator
                    #endif
                    signOutButton
                }
                Spacer().frame(height: DS.Spacing.jumbo)
            }
            .padding(DS.Spacing.xl)
            .navigationTitle("Profile")
            .task { await loadProfile() }
            .alert("Sign Out Failed", isPresented: $showSignOutError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(signOutErrorMessage)
            }
        }
    }

    private var signOutButton: some View {
        Group {
            #if DEBUG
            if DevAuthService.shared.isDevAuthActive {
                Button("Exit Dev Mode", role: .destructive) {
                    DevAuthService.shared.clearDevAuth()
                }
                .buttonStyle(.bordered)
            } else {
                clerkSignOutButton
            }
            #else
            clerkSignOutButton
            #endif
        }
    }

    private var clerkSignOutButton: some View {
        Button("Sign Out", role: .destructive) {
            Task {
                do {
                    try await clerk.auth.signOut()
                } catch is CancellationError {
                    // Ignore cancellation
                } catch {
                    signOutErrorMessage = error.localizedDescription
                    showSignOutError = true
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private func profileContent(_ profile: GQLUser) -> some View {
        VStack(spacing: DS.Spacing.xl) {
            // Avatar
            if let url = URL(string: profile.avatarUrl) {
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
                    .font(.system(size: DS.ImageSize.avatarLarge))
                    .foregroundStyle(.secondary)
            }

            Text(profile.name)
                .font(DS.Typography.title)

            if let username = profile.username {
                Text("@\(username)")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }

            if let email = profile.email {
                Text(email)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }

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
            profile = try await GraphQLClient.shared.fetchMyProfile()
        } catch {
            // Profile fetch failed — will show Clerk fallback
        }
        isLoading = false
    }

    // MARK: - Read-Only Environment Indicator (DEBUG only)

    #if DEBUG
    private var readOnlyEnvironmentIndicator: some View {
        HStack(spacing: DS.Spacing.sm) {
            Circle()
                .fill(AppConfig.useProductionServer ? .red : .green)
                .frame(width: 8, height: 8)

            Text(AppConfig.environmentName)
                .font(DS.Typography.captionBold)

            Text("·")
                .foregroundStyle(.secondary)

            Text("Sign out to switch")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
    #endif
}
