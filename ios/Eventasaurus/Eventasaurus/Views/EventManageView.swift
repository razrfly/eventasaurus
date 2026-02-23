import SwiftUI

/// Detail/management view for a user-created event.
/// Shows hero header + tabbed management interface.
struct EventManageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var event: UserEvent
    @State private var isLoading = false
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
        self.onChanged = onChanged
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Hero Header
                VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                    coverImage
                    headerSection
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.lg)

                // MARK: Tab Bar
                ManageTabBar(selectedTab: $selectedTab)

                // MARK: Tab Content
                tabContent
                    .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditSheet = true }
            }
        }
        .task { await refreshEvent() }
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
                    event = updated
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
            OrganizerSearchSheet(slug: event.slug) {
                await refreshEvent()
            }
        }
    }

    // MARK: - Cover Image

    @ViewBuilder
    private var coverImage: some View {
        if let url = event.coverImageUrl.flatMap({ URL(string: $0) }) {
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                statusPill
                visibilityPill
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

    private var statusPill: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: event.status.icon)
            Text(event.status.displayName)
        }
        .font(DS.Typography.captionBold)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(statusColor.opacity(0.15))
        .foregroundStyle(statusColor)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch event.status {
        case .draft: return .orange
        case .confirmed: return .green
        case .canceled: return .red
        case .polling: return .blue
        case .threshold: return .purple
        }
    }

    private var visibilityPill: some View {
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
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            ManageOverviewTab(
                event: $event,
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
                slug: event.slug,
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

    // MARK: - Actions

    private func refreshEvent() async {
        do {
            event = try await GraphQLClient.shared.fetchMyEvent(slug: event.slug)
            if event.status == .polling || event.status == .threshold {
                polls = (try? await GraphQLClient.shared.fetchEventPolls(slug: event.slug)) ?? []
            } else {
                polls = []
            }
            // Trigger guest list reload so pull-to-refresh updates participants
            guestRefreshID = UUID()
        } catch {
            self.error = error
        }
    }

    private func removeOrganizer(userId: String) async {
        isLoading = true
        do {
            try await GraphQLClient.shared.removeOrganizer(slug: event.slug, userId: userId)
            await refreshEvent()
        } catch {
            self.error = error
        }
        isLoading = false
    }

    private func publishEvent() async {
        isLoading = true
        do {
            event = try await GraphQLClient.shared.publishEvent(slug: event.slug)
            onChanged?()
        } catch {
            self.error = error
        }
        isLoading = false
    }

    private func cancelEvent() async {
        isLoading = true
        do {
            event = try await GraphQLClient.shared.cancelEvent(slug: event.slug)
            onChanged?()
        } catch {
            self.error = error
        }
        isLoading = false
    }

}
