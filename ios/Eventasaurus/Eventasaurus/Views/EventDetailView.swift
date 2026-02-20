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
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
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
            VStack(alignment: .leading, spacing: 16) {
                // Cover image
                if event.coverImageUrl != nil {
                    CachedImage(
                        url: event.coverImageUrl.flatMap { URL(string: $0) },
                        height: 220,
                        cornerRadius: 0
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    // Title
                    Text(event.title)
                        .font(.title2.bold())

                    // Date & time
                    if let date = event.startsAt {
                        Label {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(.subheadline)
                    }

                    // Venue
                    if let venue = event.venue {
                        if let venueSlug = venue.slug {
                            NavigationLink(value: EventDestination.venue(slug: venueSlug)) {
                                Label {
                                    VStack(alignment: .leading) {
                                        HStack(spacing: 4) {
                                            Text(venue.name)
                                                .font(.subheadline)
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let address = venue.address {
                                            Text(address)
                                                .font(.caption)
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
                                        .font(.subheadline)
                                    if let address = venue.address {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "mappin.and.ellipse")
                            }
                        }
                    }

                    // RSVP buttons
                    rsvpButtons

                    // Plan with Friends
                    planWithFriendsSection

                    // Categories
                    if let categories = event.categories, !categories.isEmpty {
                        HStack {
                            ForEach(categories, id: \.slug) { category in
                                HStack(spacing: 3) {
                                    if let icon = category.icon {
                                        Text(icon)
                                            .font(.caption2)
                                    }
                                    Text(category.name)
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(category.resolvedColor.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    }

                    Divider()

                    // Description
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
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
                .padding(.horizontal)
            }
        }
    }

    // MARK: - RSVP Buttons

    private var rsvpButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggleStatus("accepted") }
            } label: {
                Label("Going", systemImage: attendanceStatus == "accepted" ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(attendanceStatus == "accepted" ? .green : .secondary)
            .disabled(isUpdatingStatus)

            Button {
                Task { await toggleStatus("interested") }
            } label: {
                Label("Interested", systemImage: attendanceStatus == "interested" ? "star.fill" : "star")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(attendanceStatus == "interested" ? .orange : .secondary)
            .disabled(isUpdatingStatus)

            if attendeeCount > 0 {
                Text("\(attendeeCount) going")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Plan with Friends

    private var planWithFriendsSection: some View {
        Group {
            if let plan = existingPlan {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You have a plan!")
                            .font(.subheadline.weight(.medium))
                        if let count = plan.inviteCount, count > 0 {
                            Text("\(count) friends invited")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    NavigationLink(value: EventDestination.event(slug: plan.slug)) {
                        Text("View")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                }
                .padding(12)
                .background(.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Button {
                    planSheetEvent = event
                } label: {
                    Label("Plan with Friends", systemImage: "person.2.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.purple)
            }
        }
    }

    // MARK: - Data Loading

    private func loadEvent() async {
        do {
            let loaded = try await APIClient.shared.fetchEventDetail(slug: slug)
            event = loaded
            attendanceStatus = loaded.attendanceStatus
            attendeeCount = loaded.attendeeCount ?? 0

            // Load existing plan
            if let planResponse = try? await APIClient.shared.getExistingPlan(eventSlug: slug) {
                existingPlan = planResponse.plan
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }

    private func toggleStatus(_ status: String) async {
        let previousStatus = attendanceStatus
        let previousCount = attendeeCount

        // Optimistic update
        isUpdatingStatus = true
        if attendanceStatus == status {
            // Toggling off
            attendanceStatus = nil
            if status == "accepted" { attendeeCount = max(0, attendeeCount - 1) }
        } else {
            // Switching to new status
            if previousStatus == "accepted" { attendeeCount = max(0, attendeeCount - 1) }
            attendanceStatus = status
            if status == "accepted" { attendeeCount += 1 }
        }

        do {
            if previousStatus == status {
                // Remove
                _ = try await APIClient.shared.removeParticipantStatus(eventSlug: slug)
            } else {
                // Set new status
                let response = try await APIClient.shared.updateParticipantStatus(eventSlug: slug, status: status)
                if let count = response.participantCount {
                    attendeeCount = count
                }
            }
        } catch {
            // Revert on error
            attendanceStatus = previousStatus
            attendeeCount = previousCount
        }
        isUpdatingStatus = false
    }
}
