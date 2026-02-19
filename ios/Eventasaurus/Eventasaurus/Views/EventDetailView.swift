import SwiftUI

struct EventDetailView: View {
    let slug: String
    @State private var event: Event?
    @State private var isLoading = true
    @State private var error: Error?

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

                    // Attendee count
                    if let count = event.attendeeCount {
                        Label("\(count) attending", systemImage: "person.2")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

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

    private func loadEvent() async {
        do {
            event = try await APIClient.shared.fetchEventDetail(slug: slug)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
