import SwiftUI

/// Detail/management view for a user-created event.
/// Shows event details with edit, publish, cancel, and delete actions.
struct EventManageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var event: UserEvent
    @State private var isLoading = false
    @State private var showEditSheet = false
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
                statsSection
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
    }

    // MARK: - Cover Image

    @ViewBuilder
    private var coverImage: some View {
        if let url = event.coverImageUrl.flatMap({ URL(string: $0) }) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .foregroundStyle(.quaternary)
                    .overlay { ProgressView() }
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

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: DS.Spacing.xl) {
            statItem(
                icon: "person.2.fill",
                value: "\(event.participantCount)",
                label: "Attendees"
            )

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

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        VStack(spacing: DS.Spacing.md) {
            if event.status == .draft {
                Button {
                    Task { await publishEvent() }
                } label: {
                    Label("Publish Event", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary)
            }

            if event.status == .confirmed {
                Button(role: .destructive) {
                    Task { await cancelEvent() }
                } label: {
                    Label("Cancel Event", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassSecondary)
            }
        }
    }

    // MARK: - Actions

    private func refreshEvent() async {
        do {
            event = try await GraphQLClient.shared.fetchMyEvent(slug: event.slug)
        } catch {
            self.error = error
        }
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
