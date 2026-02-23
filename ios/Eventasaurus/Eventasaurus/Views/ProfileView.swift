import SwiftUI
import ClerkKit
import ClerkKitUI

struct ProfileView: View {
    @Environment(Clerk.self) private var clerk
    @State private var profile: GQLUser?
    @State private var isLoading = true
    @State private var showSignOutError = false
    @State private var signOutErrorMessage = ""
    #if DEBUG
    @State private var showDevPicker = false
    @State private var showEnvironmentConfirm = false
    #endif

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

                #if DEBUG
                devSettingsSection
                #else
                signOutButton
                #endif
                Spacer().frame(height: DS.Spacing.jumbo)
            }
            .padding(DS.Spacing.xl)
            .navigationTitle("Profile")
            .task { await loadProfile() }
            #if DEBUG
            .sheet(isPresented: $showDevPicker) {
                DevUserPickerView()
            }
            #endif
            .alert("Sign Out Failed", isPresented: $showSignOutError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(signOutErrorMessage)
            }
            #if DEBUG
            .confirmationDialog(
                environmentConfirmTitle,
                isPresented: $showEnvironmentConfirm,
                titleVisibility: .visible
            ) {
                Button(environmentConfirmAction, role: environmentConfirmRole) {
                    let envService = DevEnvironmentService.shared
                    envService.setProduction(!envService.isRunningProduction)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(environmentConfirmMessage)
            }
            #endif
        }
    }

    private var signOutButton: some View {
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

    // MARK: - Dev Settings (DEBUG only)

    #if DEBUG
    private var devSettingsSection: some View {
        VStack(spacing: DS.Spacing.lg) {
            // Environment indicator
            environmentStatusView

            // Dev auth controls (only available on development server)
            if !AppConfig.useProductionServer {
                if DevAuthService.shared.isDevAuthActive {
                    VStack(spacing: DS.Spacing.md) {
                        Text("Dev Mode: \(DevAuthService.shared.selectedUserName ?? "Unknown")")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)

                        Button("Switch Dev User") {
                            showDevPicker = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)

                        Button("Exit Dev Mode", role: .destructive) {
                            DevAuthService.shared.clearDevAuth()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    signOutButton
                }
            } else {
                signOutButton
            }
        }
    }

    private var environmentStatusView: some View {
        let envService = DevEnvironmentService.shared

        return VStack(spacing: DS.Spacing.sm) {
            if AppConfig.useProductionServer {
                Label("Production Server", systemImage: "server.rack")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            } else {
                Label("Development Server", systemImage: "laptopcomputer")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }

            if envService.needsRestart {
                Label("Restart app to apply", systemImage: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Button(AppConfig.useProductionServer ? "Switch to Development" : "Switch to Production") {
                showEnvironmentConfirm = true
            }
            .buttonStyle(.bordered)
            .tint(AppConfig.useProductionServer ? .green : .red)
            .controlSize(.small)
        }
        .padding(DS.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private var environmentConfirmTitle: String {
        AppConfig.useProductionServer
            ? "Switch to Development?"
            : "Switch to Production?"
    }

    private var environmentConfirmAction: String {
        AppConfig.useProductionServer
            ? "Switch to Development"
            : "Switch to Production"
    }

    private var environmentConfirmRole: ButtonRole? {
        AppConfig.useProductionServer ? nil : .destructive
    }

    private var environmentConfirmMessage: String {
        if AppConfig.useProductionServer {
            return "This will connect to localhost:4000 on next restart. Dev auth will be available again."
        } else {
            return "This will connect to the live wombie.com server on next restart. Dev auth will be disabled — you'll need to sign in with real credentials."
        }
    }
    #endif
}
