import SwiftUI

struct EventDetailView: View {
    let slug: String
    @State private var event: Event?
    @State private var isLoading = true
    @State private var error: Error?

    // RSVP state
    @State private var attendanceStatus: String?
    @State private var attendeeCount: Int = 0
    @State private var isUpdatingStatus = false

    // Plan with Friends state
    @State private var existingPlan: PlanInfo?
    @State private var planSheetEvent: Event?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let event {
                eventContent(event)
            } else if let error {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    message: error.localizedDescription
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvent() }
        .sheet(item: $planSheetEvent) { event in
            PlanWithFriendsSheet(event: event) { plan in
                existingPlan = plan
            }
        }
    }

    private func eventContent(_ event: Event) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Edge-to-edge hero image
                if event.coverImageUrl != nil {
                    CachedImage(
                        url: event.coverImageUrl.flatMap { URL(string: $0) },
                        height: DS.ImageSize.hero,
                        cornerRadius: 0
                    )
                }

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Title
                    Text(event.title)
                        .font(DS.Typography.title)

                    // Date & time
                    if let date = event.startsAt {
                        Label {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(DS.Typography.body)
                    }

                    // Venue
                    if let venue = event.venue {
                        venueRow(venue)
                    }

                    // RSVP buttons
                    rsvpButtons

                    // Plan with Friends
                    planWithFriendsSection(for: event)

                    // Categories
                    if let categories = event.categories, !categories.isEmpty {
                        HStack(spacing: DS.Spacing.md) {
                            ForEach(categories, id: \.slug) { category in
                                HStack(spacing: DS.Spacing.xxs) {
                                    if let icon = category.icon {
                                        Text(icon)
                                            .font(DS.Typography.micro)
                                    }
                                    Text(category.name)
                                }
                                .font(DS.Typography.caption)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(category.resolvedColor.opacity(DS.Opacity.tintedBackground))
                                .clipShape(Capsule())
                            }
                        }
                    }

                    Divider()

                    // Description
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(DS.Typography.prose)
                    }

                    // Ticket link
                    if let ticketUrl = event.ticketUrl, let url = URL(string: ticketUrl) {
                        ExternalLinkButton(title: "Get Tickets", url: url, icon: "ticket")
                    }

                    // Venue map
                    if let venue = event.venue, let lat = venue.lat, let lng = venue.lng {
                        VenueMapCard(name: venue.name, address: venue.address, lat: lat, lng: lng)
                    }

                    // Source attribution
                    if let sources = event.sources, !sources.isEmpty {
                        Divider()
                        SourceAttributionSection(sources: sources)
                    }

                    // Nearby events
                    if let nearbyEvents = event.nearbyEvents, !nearbyEvents.isEmpty {
                        Divider()
                        NearbyEventsSection(events: nearbyEvents)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
        }
    }

    // MARK: - Venue Row

    @ViewBuilder
    private func venueRow(_ venue: Venue) -> some View {
        if let venueSlug = venue.slug {
            NavigationLink(value: EventDestination.venue(slug: venueSlug)) {
                Label {
                    VStack(alignment: .leading) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text(venue.name)
                                .font(DS.Typography.body)
                            Image(systemName: "chevron.right")
                                .font(DS.Typography.micro)
                                .foregroundStyle(.secondary)
                        }
                        if let address = venue.address {
                            Text(address)
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
            }
            .buttonStyle(.plain)
        } else {
            Label {
                VStack(alignment: .leading) {
                    Text(venue.name)
                        .font(DS.Typography.body)
                    if let address = venue.address {
                        Text(address)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
        }
    }

    // MARK: - RSVP Buttons

    private var rsvpButtons: some View {
        HStack(spacing: DS.Spacing.lg) {
            Button {
                Task { await toggleStatus("accepted") }
            } label: {
                Label("Going", systemImage: attendanceStatus == "accepted" ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(DS.Typography.bodyMedium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(attendanceStatus == "accepted" ? DS.Colors.going : .secondary)
            .disabled(isUpdatingStatus)
            .accessibilityLabel("Going")
            .accessibilityValue(attendanceStatus == "accepted" ? "Selected" : "Not selected")
            .accessibilityHint("Double tap to mark as going")

            Button {
                Task { await toggleStatus("interested") }
            } label: {
                Label("Interested", systemImage: attendanceStatus == "interested" ? "star.fill" : "star")
                    .font(DS.Typography.bodyMedium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(attendanceStatus == "interested" ? DS.Colors.interested : .secondary)
            .disabled(isUpdatingStatus)
            .accessibilityLabel("Interested")
            .accessibilityValue(attendanceStatus == "interested" ? "Selected" : "Not selected")
            .accessibilityHint("Double tap to mark as interested")

            if attendeeCount > 0 {
                Text("\(attendeeCount) going")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: - Plan with Friends

    private func planWithFriendsSection(for event: Event) -> some View {
        Group {
            if let plan = existingPlan {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(DS.Colors.plan)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("You have a plan!")
                            .font(DS.Typography.bodyMedium)
                        if let count = plan.inviteCount, count > 0 {
                            Text("\(count) friends invited")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    NavigationLink(value: EventDestination.event(slug: plan.slug)) {
                        Text("View")
                            .font(DS.Typography.captionMedium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Colors.plan)
                    .controlSize(.small)
                }
                .padding(DS.Spacing.lg)
                .glassBackground(cornerRadius: DS.Radius.md)
                .accessibilityElement(children: .combine)
            } else {
                Button {
                    planSheetEvent = event
                } label: {
                    Label("Plan with Friends", systemImage: "person.2.badge.plus")
                        .font(DS.Typography.bodyMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(DS.Colors.plan)
                .accessibilityHint("Opens sheet to invite friends")
            }
        }
    }

    // MARK: - Data Loading

    private func loadEvent() async {
        defer { isLoading = false }
        do {
            let loaded = try await APIClient.shared.fetchEventDetail(slug: slug)
            event = loaded
            attendanceStatus = loaded.attendanceStatus
            attendeeCount = loaded.attendeeCount ?? 0

            if let planResponse = try? await APIClient.shared.getExistingPlan(eventSlug: slug) {
                existingPlan = planResponse.plan
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }

    private func toggleStatus(_ status: String) async {
        let previousStatus = attendanceStatus
        let previousCount = attendeeCount

        isUpdatingStatus = true
        withAnimation(DS.Animation.spring) {
            if attendanceStatus == status {
                attendanceStatus = nil
                if status == "accepted" { attendeeCount = max(0, attendeeCount - 1) }
            } else {
                if previousStatus == "accepted" { attendeeCount = max(0, attendeeCount - 1) }
                attendanceStatus = status
                if status == "accepted" { attendeeCount += 1 }
            }
        }

        do {
            if previousStatus == status {
                _ = try await APIClient.shared.removeParticipantStatus(eventSlug: slug)
            } else {
                let response = try await APIClient.shared.updateParticipantStatus(eventSlug: slug, status: status)
                if let count = response.participantCount {
                    attendeeCount = count
                }
            }
        } catch {
            withAnimation(DS.Animation.spring) {
                attendanceStatus = previousStatus
                attendeeCount = previousCount
            }
        }
        isUpdatingStatus = false
    }
}
