import SwiftUI

/// Overview tab content for event management — details, venue, organizers, stats, threshold, actions.
struct ManageOverviewTab: View {
    @Binding var event: UserEvent
    let polls: [EventPoll]
    let isLoading: Bool
    var onEdit: () -> Void
    var onInvite: () -> Void
    var onOrganizerSearch: () -> Void
    var onPublish: () -> Void
    var onCancel: () -> Void
    var onRemoveOrganizer: (String) -> Void
    var onParticipantsChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
            detailsSection
            venueSection
            organizersSection
            statsSection
            thresholdSection
            actionsSection
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, DS.Spacing.md)
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
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

            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(DS.Typography.prose)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        } else if let venue = event.venue {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "building.2")
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(venue.name)
                        .font(DS.Typography.bodyMedium)
                    if let address = venue.address {
                        Text(address)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        onOrganizerSearch()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }

                ForEach(organizers) { organizer in
                    HStack(spacing: DS.Spacing.md) {
                        DiceBearAvatar(email: organizer.email, url: organizer.avatarUrl.flatMap { URL(string: $0) }, size: 32)

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
                                onRemoveOrganizer(organizer.id)
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
                ParticipantListView(event: event) { onParticipantsChanged() }
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
                        onPublish()
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

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        VStack(spacing: DS.Spacing.md) {
            if event.status != .draft && event.status != .canceled {
                Button {
                    onInvite()
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
                    onPublish()
                } label: {
                    Label("Publish Event", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary)
                .disabled(isLoading)
            }

            if event.status == .confirmed {
                Button(role: .destructive) {
                    onCancel()
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
}
