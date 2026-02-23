import SwiftUI

struct VenueDetailView: View {
    let slug: String
    @State private var response: VenueDetailResponse?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let response {
                venueContent(response)
            } else if let error {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    message: error.localizedDescription
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadVenue() }
    }

    private func venueContent(_ data: VenueDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Cover image
                if let urlString = data.venue.coverImageUrl, let url = URL(string: urlString) {
                    CachedImage(
                        url: url,
                        height: DS.ImageSize.hero,
                        cornerRadius: 0,
                        placeholderIcon: "building.2"
                    )
                }

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Venue name
                    Text(data.venue.displayName)
                        .font(DS.Typography.title)

                    // Address & location
                    if let address = data.venue.address, !address.isEmpty {
                        Label {
                            Text(address)
                                .font(DS.Typography.body)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }

                    // City & country
                    if let cityName = data.venue.cityName {
                        Label {
                            if let country = data.venue.country {
                                Text("\(cityName), \(country)")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(cityName)
                                    .font(DS.Typography.body)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }

                    // Map card
                    if let lat = data.venue.lat, let lng = data.venue.lng {
                        VenueMapCard(
                            name: data.venue.displayName,
                            address: data.venue.address,
                            lat: lat,
                            lng: lng
                        )
                    }

                    Divider()

                    // Upcoming events
                    if data.events.isEmpty {
                        EmptyStateView(
                            icon: "calendar.badge.exclamationmark",
                            title: "No Upcoming Events",
                            message: "No upcoming events at this venue."
                        )
                    } else {
                        SectionHeader(
                            title: "Upcoming Events",
                            subtitle: data.venue.eventCount.map { "\($0) event\($0 == 1 ? "" : "s")" }
                        )

                        LazyVStack(alignment: .leading, spacing: DS.Spacing.xl) {
                            ForEach(data.events) { event in
                                NavigationLink(value: EventDestination.event(slug: event.slug)) {
                                    EventCardView(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
        }
    }

    private func loadVenue() async {
        do {
            response = try await APIClient.shared.fetchVenueDetail(slug: slug)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            self.error = error
            isLoading = false
        }
    }
}
