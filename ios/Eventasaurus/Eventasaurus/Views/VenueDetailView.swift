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
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadVenue() }
    }

    private func venueContent(_ data: VenueDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Cover image
                if let urlString = data.venue.coverImageUrl, let url = URL(string: urlString) {
                    CachedImage(
                        url: url,
                        height: 220,
                        cornerRadius: 0,
                        placeholderIcon: "building.2"
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    // Venue name
                    Text(data.venue.name)
                        .font(.title2.bold())

                    // Address & location
                    if let address = data.venue.address, !address.isEmpty {
                        Label {
                            Text(address)
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }

                    // City & country
                    if let cityName = data.venue.cityName {
                        Label {
                            if let country = data.venue.country {
                                Text("\(cityName), \(country)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(cityName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }

                    // Map card
                    if let lat = data.venue.lat, let lng = data.venue.lng {
                        VenueMapCard(
                            name: data.venue.name,
                            address: data.venue.address,
                            lat: lat,
                            lng: lng
                        )
                    }

                    Divider()

                    // Upcoming events
                    if data.events.isEmpty {
                        ContentUnavailableView {
                            Label("No Upcoming Events", systemImage: "calendar.badge.exclamationmark")
                        } description: {
                            Text("No upcoming events at this venue.")
                        }
                    } else {
                        HStack {
                            Text("Upcoming Events")
                                .font(.headline)
                            Spacer()
                            if let count = data.venue.eventCount {
                                Text("\(count) event\(count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(data.events) { event in
                                NavigationLink(value: EventDestination.event(slug: event.slug)) {
                                    EventCardView(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
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
