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
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await loadVenue() }
    }

    private func venueContent(_ data: VenueDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Hero with overlaid name/address/city
                if AppConfig.resolvedImageURL(data.venue.coverImageUrl) != nil {
                    DramaticHero(
                        imageURL: AppConfig.resolvedImageURL(data.venue.coverImageUrl),
                        placeholderIcon: "building.2"
                    ) {
                        HeroOverlayCard {
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                Text(data.venue.displayName)
                                    .font(DS.Typography.title)
                                    .foregroundStyle(.white)

                                if let address = data.venue.address, !address.isEmpty {
                                    Label {
                                        Text(address)
                                    } icon: {
                                        Image(systemName: "mappin.and.ellipse")
                                    }
                                    .font(DS.Typography.body)
                                    .foregroundStyle(.white.opacity(0.9))
                                }

                                if let cityName = data.venue.cityName {
                                    Label {
                                        if let country = data.venue.country {
                                            Text("\(cityName), \(country)")
                                        } else {
                                            Text(cityName)
                                        }
                                    } icon: {
                                        Image(systemName: "globe")
                                    }
                                    .font(DS.Typography.body)
                                    .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                    }
                } else {
                    // No-image fallback: inline title
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(data.venue.displayName)
                            .font(DS.Typography.title)

                        if let address = data.venue.address, !address.isEmpty {
                            Label(address, systemImage: "mappin.and.ellipse")
                                .font(DS.Typography.body)
                        }

                        if let cityName = data.venue.cityName {
                            let location = data.venue.country.map { "\(cityName), \($0)" } ?? cityName
                            Label(location, systemImage: "globe")
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.top, DS.Spacing.xl)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
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
                                    EventStandardCard(event: event) {
                                        HStack {
                                            if let category = event.primaryCategory {
                                                DiscoverBadges.categoryBadge(category)
                                            }
                                            Spacer()
                                            if let badge = event.timeBadgeText() {
                                                DiscoverBadges.timeBadge(badge)
                                            }
                                        }
                                    } subtitleContent: {
                                        if let date = event.startsAt {
                                            Text(date, style: .date)
                                                .font(DS.Typography.body)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
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
