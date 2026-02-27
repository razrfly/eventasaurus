import SwiftUI

/// Detail/management view for a user-created event.
/// Shows hero header + tabbed management interface.
struct EventManageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarSafeAreaInset) private var tabBarSafeAreaInset
    @State private var event: UserEvent?
    @State private var slug: String
    @State private var isLoading = false
    @State private var isInitialLoading: Bool
    @State private var showEditSheet = false
    @State private var showInviteSheet = false
    @State private var showOrganizerSearch = false
    @State private var polls: [EventPoll] = []
    @State private var error: Error?
    @State private var selectedTab: ManageTab = .overview
    @State private var guestRefreshID = UUID()

    var onChanged: (() -> Void)?

    init(event: UserEvent, onChanged: (() -> Void)? = nil) {
        _event = State(initialValue: event)
        _slug = State(initialValue: event.slug)
        _isInitialLoading = State(initialValue: false)
        self.onChanged = onChanged
    }

    /// Slug-based init — loads the event data on appear.
    init(slug: String, onChanged: (() -> Void)? = nil) {
        _event = State(initialValue: nil)
        _slug = State(initialValue: slug)
        _isInitialLoading = State(initialValue: true)
        self.onChanged = onChanged
    }

    var body: some View {
        Group {
            if let event {
                eventContent(event)
            } else if isInitialLoading {
                ProgressView("Loading event...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Event Not Found",
                    message: error?.localizedDescription ?? "Could not load this event.",
                    actionTitle: "Try Again",
                    action: { Task { await loadEvent() } }
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isInitialLoading {
                await loadEvent()
            } else {
                await refreshEvent()
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func eventContent(_ event: UserEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                    coverImage(for: event)
                    headerSection(for: event)
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.lg)

                ManageTabBar(selectedTab: $selectedTab)

                tabContent(for: event)
                    .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .safeAreaInset(edge: .bottom) {
            attendeeViewBanner(for: event)
                .padding(.bottom, tabBarSafeAreaInset)
        }
        .navigationTitle(event.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditSheet = true }
            }
        }
        .refreshable { await refreshEvent() }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "Something went wrong")
        }
        .sheet(isPresented: $showEditSheet) {
            EventEditView(
                event: event,
                onUpdated: { updated in
                    self.event = updated
                    onChanged?()
                },
                onDeleted: {
                    onChanged?()
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteGuestsSheet(event: event) { count in
                if count > 0 {
                    Task { await refreshEvent() }
                    onChanged?()
                }
            }
        }
        .sheet(isPresented: $showOrganizerSearch) {
            OrganizerSearchSheet(slug: slug) {
                await refreshEvent()
            }
        }
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImage(for event: UserEvent) -> some View {
        if let url = AppConfig.resolvedImageURL(event.coverImageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .foregroundStyle(.quaternary)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                case .empty:
                    Rectangle()
                        .foregroundStyle(.quaternary)
                        .overlay { ProgressView() }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: DS.ImageSize.hero)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
        }
    }

    // MARK: - Header

    private func headerSection(for event: UserEvent) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                statusPill(for: event)
                visibilityPill(for: event)
                Spacer()
            }

            Text(event.title)
                .font(DS.Typography.title)

            if let tagline = event.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(DS.Typography.bodyItalic)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusPill(for event: UserEvent) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: event.status.icon)
            Text(event.status.displayName)
        }
        .font(DS.Typography.captionBold)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(event.status.color.opacity(0.15))
        .foregroundStyle(event.status.color)
        .clipShape(Capsule())
    }

    private func visibilityPill(for event: UserEvent) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: event.visibility.icon)
            Text(event.visibility.displayName)
        }
        .font(DS.Typography.captionBold)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(Color.secondary.opacity(0.1))
        .foregroundStyle(.secondary)
        .clipShape(Capsule())
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for event: UserEvent) -> some View {
        let eventBinding = Binding<UserEvent>(
            get: { self.event ?? event },
            set: { self.event = $0 }
        )

        switch selectedTab {
        case .overview:
            ManageOverviewTab(
                event: eventBinding,
                polls: polls,
                isLoading: isLoading,
                onEdit: { showEditSheet = true },
                onInvite: { showInviteSheet = true },
                onOrganizerSearch: { showOrganizerSearch = true },
                onPublish: { Task { await publishEvent() } },
                onCancel: { Task { await cancelEvent() } },
                onRemoveOrganizer: { userId in Task { await removeOrganizer(userId: userId) } },
                onParticipantsChanged: {
                    Task { await refreshEvent() }
                    onChanged?()
                }
            )

        case .guests:
            ManageGuestsTab(
                event: event,
                onInvite: { showInviteSheet = true },
                onParticipantsChanged: {
                    Task { await refreshEvent() }
                    onChanged?()
                }
            )

        case .polls:
            ManagePollsTab(
                polls: polls,
                slug: slug,
                eventId: event.id,
                eventStatus: event.status,
                onRefresh: { await refreshEvent() }
            )

        case .insights:
            ManageInsightsTab()

        case .history:
            ManageHistoryTab()
        }
    }

    // MARK: - Banners

    private func attendeeViewBanner(for event: UserEvent) -> some View {
        GlassActionBar {
            NavigationLink {
                EventDetailView(slug: event.slug)
            } label: {
                HStack {
                    Label("See attendee view", systemImage: "person.2")
                        .font(DS.Typography.bodyMedium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(DS.Typography.micro)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func loadEvent() async {
        do {
            try await fetchEventAndPolls()
            isInitialLoading = false
        } catch {
            self.error = error
            isInitialLoading = false
        }
    }

    private func refreshEvent() async {
        do {
            try await fetchEventAndPolls()
            guestRefreshID = UUID()
        } catch {
            self.error = error
        }
    }

    private func fetchEventAndPolls() async throws {
        event = try await GraphQLClient.shared.fetchMyEvent(slug: slug)
        do {
            polls = try await GraphQLClient.shared.fetchEventPolls(slug: slug)
        } catch {
            // Leave existing polls unchanged on failure
        }
    }

    private func removeOrganizer(userId: String) async {
        isLoading = true
        do {
            try await GraphQLClient.shared.removeOrganizer(slug: slug, userId: userId)
            await refreshEvent()
        } catch {
            self.error = error
        }
        isLoading = false
    }

    private func publishEvent() async {
        isLoading = true
        do {
            event = try await GraphQLClient.shared.publishEvent(slug: slug)
            onChanged?()
        } catch {
            self.error = error
        }
        isLoading = false
    }

    private func cancelEvent() async {
        isLoading = true
        do {
            event = try await GraphQLClient.shared.cancelEvent(slug: slug)
            onChanged?()
        } catch {
            self.error = error
        }
        isLoading = false
    }

}
