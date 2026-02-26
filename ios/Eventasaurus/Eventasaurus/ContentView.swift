import SwiftUI
import ClerkKit
import ClerkKitUI

struct ContentView: View {
    @Environment(Clerk.self) private var clerk
    @State private var showAuth = false
    @Binding var deepLinkSlug: String?
    /// Local copy so sheet content stays stable during the dismiss animation.
    @State private var presentedSlug: String?
    @State private var selectedTab: AppTab = .home
    @State private var upcomingEventCount: Int = 0
    #if DEBUG
    @State private var showDevPicker = false
    @State private var showEnvironmentConfirm = false
    #endif

    private var isAuthenticated: Bool {
        #if DEBUG
        return clerk.user != nil || DevAuthService.shared.isDevAuthActive
        #else
        return clerk.user != nil
        #endif
    }

    var body: some View {
        Group {
            if !clerk.isLoaded {
                ProgressView("Loading...")
            } else if isAuthenticated {
                mainTabView
            } else {
                signedOutView
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthView(mode: .signIn)
        }
        .onChange(of: deepLinkSlug) { _, newValue in
            if let newValue {
                presentedSlug = newValue
            }
        }
        .sheet(isPresented: Binding(
            get: { presentedSlug != nil },
            set: { if !$0 { presentedSlug = nil; deepLinkSlug = nil } }
        )) {
            if let slug = presentedSlug {
                NavigationStack {
                    EventDetailView(slug: slug)
                }
            }
        }
    }

    private var mainTabView: some View {
        VStack(spacing: 0) {
            #if DEBUG
            if AppConfig.useProductionServer {
                productionBanner
            }
            #endif

            TabView(selection: $selectedTab) {
                MyEventsView(upcomingCount: $upcomingEventCount)
                    .tag(AppTab.home)
                    .toolbar(.hidden, for: .tabBar)

                DiscoverView()
                    .tag(AppTab.discover)
                    .toolbar(.hidden, for: .tabBar)

                ChatView()
                    .tag(AppTab.chat)
                    .toolbar(.hidden, for: .tabBar)
            }
            .safeAreaInset(edge: .bottom) {
                GlassTabBar(selectedTab: $selectedTab, eventCount: upcomingEventCount)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.lg)
            }
        }
    }

    #if DEBUG
    private var productionBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("PRODUCTION SERVER")
        }
        .font(.caption2.bold())
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(.red)
    }
    #endif

    // MARK: - Signed-Out Screen

    private var signedOutView: some View {
        VStack(spacing: 0) {
            #if DEBUG
            environmentPill
                .padding(.top, DS.Spacing.md)
            #endif

            Spacer()

            // Centered branding + sign in
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

            Spacer()

            #if DEBUG
            devToolsSection
                .padding(.bottom, DS.Spacing.lg)
            #endif
        }
        .padding(.horizontal, DS.Spacing.xl)
        #if DEBUG
        .sheet(isPresented: $showDevPicker) {
            DevUserPickerView()
        }
        .confirmationDialog(
            environmentConfirmTitle,
            isPresented: $showEnvironmentConfirm,
            titleVisibility: .visible
        ) {
            Button(environmentConfirmAction, role: environmentConfirmRole) {
                let envService = DevEnvironmentService.shared
                envService.setProduction(!envService.isRunningProduction)
                exit(0)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(environmentConfirmMessage)
        }
        #endif
    }

    // MARK: - Environment Pill & Dev Tools (DEBUG only)

    #if DEBUG
    private var environmentPill: some View {
        Button {
            showEnvironmentConfirm = true
        } label: {
            EnvironmentBadge(subtitle: AppConfig.environmentHost)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var devToolsSection: some View {
        VStack(spacing: DS.Spacing.md) {
            if AppConfig.useProductionServer {
                // Production mode — no dev tools
                Divider()
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("PRODUCTION MODE")
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(.red)
                }

                Text("Connected to live server. Dev tools disabled.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                // Development mode — inline quick-login
                Divider()
                Text("DEV TOOLS")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(.orange)

                inlineQuickLoginUsers
            }
        }
    }

    private var inlineQuickLoginUsers: some View {
        VStack(spacing: DS.Spacing.xs) {
            let devAuth = DevAuthService.shared

            if devAuth.isLoadingUsers {
                ProgressView()
                    .controlSize(.small)
            } else if let users = devAuth.users {
                let flattened = flattenedUsers(users, limit: 5)
                ForEach(flattened) { user in
                    Button {
                        devAuth.selectUser(id: user.id, name: user.name ?? user.email)
                    } label: {
                        HStack(spacing: DS.Spacing.md) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(user.name ?? user.email)
                                    .font(DS.Typography.body)
                                Text(user.label)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, DS.Spacing.xs)
                        .padding(.horizontal, DS.Spacing.md)
                    }
                    .buttonStyle(.plain)
                }

                Button("Show All Users") {
                    showDevPicker = true
                }
                .font(DS.Typography.caption)
                .tint(.orange)
                .padding(.top, DS.Spacing.xs)
            } else {
                Text("Could not load dev users")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if DevAuthService.shared.users == nil {
                await DevAuthService.shared.fetchUsers()
            }
        }
    }

    private func flattenedUsers(_ users: DevQuickLoginUsers, limit: Int) -> [DevUser] {
        let all = users.personal + users.organizers + users.participants
        var seen = Set<String>()
        let unique = all.filter { user in
            guard !seen.contains(user.id) else { return false }
            seen.insert(user.id)
            return true
        }
        return Array(unique.prefix(limit))
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
            return "The app will quit. Reopen manually to connect to the development server. Dev auth will be available again."
        } else {
            return "The app will quit. Reopen manually to connect to the production server. You'll need to sign in with real credentials."
        }
    }
    #endif
}

#Preview("Signed Out") {
    ContentView(deepLinkSlug: .constant(nil))
        .environment(Clerk.preview { preview in
            preview.isSignedIn = false
        })
}
