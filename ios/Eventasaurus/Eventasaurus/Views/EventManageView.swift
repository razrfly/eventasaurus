import SwiftUI

/// Detail/management view for a user-created event.
/// Shows event details with edit, publish, cancel, and delete actions.
struct EventManageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var event: UserEvent
    @State private var isLoading = false
    @State private var showEditSheet = false
    @State private var showInviteSheet = false
    @State private var showOrganizerSearch = false
    @State private var polls: [EventPoll] = []
    @State private var error: Error?

    var onChanged: (() -> Void)?

    init(event: UserEvent, onChanged: (() -> Void)? = nil) {
        _event = State(initialValue: event)
        self.onChanged = onChanged
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                coverImage
                headerSection
                detailsSection
                venueSection
                organizersSection
                statsSection
                thresholdSection
                pollsSection
                actionsSection
            }
            .padding(DS.Spacing.xl)
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
            // Status + visibility row
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

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            // Date/time
            if let date = event.startsAt {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "calendar")
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .font(DS.Typography.bodyMedium)
                        Text(date, format: .dateTime.hour().minute())
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                        if let endsAt = event.endsAt {
                            Text("Ends \(endsAt, format: .dateTime.hour().minute())")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Timezone
            if let tz = event.timezone {
                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "globe")
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    Text(tz)
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Description
            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(DS.Typography.prose)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Venue

    @ViewBuilder
    private var venueSection: some View {
        if event.isVirtual {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "video")
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Virtual Event")
                        .font(DS.Typography.bodyMedium)
                    if let url = event.virtualVenueUrl {
                        Text(url)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .cardStyle()
        } else if let venue = event.venue {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(venue.name)
                        .font(DS.Typography.bodyMedium)
                    if let address = venue.address {
                        Text(address)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Organizers

    @ViewBuilder
    private var organizersSection: some View {
        if let organizers = event.organizers, !organizers.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Text("Organizers")
                        .font(DS.Typography.bodyBold)
                    Spacer()
                    Button {
                        showOrganizerSearch = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }

                ForEach(organizers) { organizer in
                    HStack(spacing: DS.Spacing.md) {
                        DiceBearAvatar(url: organizer.avatarUrl.flatMap { URL(string: $0) }, size: 32)

                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(organizer.name)
                                .font(DS.Typography.bodyMedium)
                            if let email = organizer.email {
                                Text(email)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if organizers.count > 1 {
                            Button(role: .destructive) {
                                Task { await removeOrganizer(userId: organizer.id) }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: DS.Spacing.xl) {
            NavigationLink {
                ParticipantListView(event: event) {
                    Task { await refreshEvent() }
                }
            } label: {
                statItem(
                    icon: "person.2.fill",
                    value: "\(event.participantCount)",
                    label: "Attendees"
                )
            }
            .buttonStyle(.plain)

            if let theme = event.theme {
                statItem(
                    icon: "paintpalette.fill",
                    value: theme.displayName,
                    label: "Theme"
                )
            }

            if event.isTicketed {
                statItem(
                    icon: "ticket.fill",
                    value: "Yes",
                    label: "Ticketed"
                )
            }
        }
        .cardStyle()
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(DS.Typography.bodyBold)
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Threshold

    @ViewBuilder
    private var thresholdSection: some View {
        if event.status == .threshold, let thresholdCount = event.thresholdCount, thresholdCount > 0 {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Threshold Progress")
                    .font(DS.Typography.bodyBold)

                let current = event.participantCount
                let progress = min(Double(current) / Double(thresholdCount), 1.0)

                ProgressView(value: progress) {
                    HStack {
                        Text("\(current) of \(thresholdCount) needed")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(DS.Typography.captionBold)
                            .foregroundStyle(progress >= 1.0 ? .green : .purple)
                    }
                }
                .tint(progress >= 1.0 ? .green : .purple)

                if progress >= 1.0 {
                    Button {
                        Task { await publishEvent() }
                    } label: {
                        Label("Announce to Attendees", systemImage: "megaphone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassPrimary)
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Polls

    @ViewBuilder
    private var pollsSection: some View {
        if !polls.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Text("Polls")
                    .font(DS.Typography.bodyBold)

                ForEach(polls) { poll in
                    PollCardView(poll: poll, slug: event.slug)
                }
            }
        } else if event.status == .polling {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Image(systemName: "chart.bar")
                        .foregroundStyle(.blue)
                    Text("No polls yet")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        VStack(spacing: DS.Spacing.md) {
            if event.status != .draft && event.status != .canceled {
                Button {
                    showInviteSheet = true
                } label: {
                    Label("Invite Guests", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassSecondary)
            }

            if let shareURL = URL.event(slug: event.slug) {
                ShareLink(
                    item: shareURL,
                    subject: Text(event.title),
                    message: Text(event.tagline ?? event.title)
                ) {
                    Label("Share Event", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassSecondary)
            }

            if event.status == .draft {
                Button {
                    Task { await publishEvent() }
                } label: {
                    Label("Publish Event", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary)
                .disabled(isLoading)
            }

            if event.status == .confirmed {
                Button(role: .destructive) {
                    Task { await cancelEvent() }
                } label: {
                    Label("Cancel Event", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassSecondary)
                .disabled(isLoading)
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            }
        }
    }

    // MARK: - Actions

    private func refreshEvent() async {
        do {
            event = try await GraphQLClient.shared.fetchMyEvent(slug: event.slug)
            // Load polls if event supports them, clear if not
            if event.status == .polling || event.status == .threshold {
                polls = (try? await GraphQLClient.shared.fetchEventPolls(slug: event.slug)) ?? []
            } else {
                polls = []
            }
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
