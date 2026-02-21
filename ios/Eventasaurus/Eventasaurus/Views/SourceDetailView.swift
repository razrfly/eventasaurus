import SwiftUI

struct SourceDetailView: View {
    let slug: String
    let cityId: Int?
    @State private var response: SourceDetailResponse?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var selectedCityId: Int?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let response {
                sourceContent(response)
            } else if let error {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    message: error.localizedDescription
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedCityId = cityId }
        .task(id: selectedCityId) {
            await loadSource()
        }
    }

    private func sourceContent(_ data: SourceDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Themed hero card
                sourceHero(data.source)

                // Website link
                if let websiteUrl = data.source.websiteUrl, let url = URL(string: websiteUrl) {
                    ExternalLinkButton(title: "Visit Website", url: url, icon: "globe")
                        .padding(.horizontal, DS.Spacing.xl)
                }

                // City filter pills
                if let cities = data.availableCities, cities.count > 1 {
                    cityPicker(cities)
                }

                Divider()
                    .padding(.horizontal, DS.Spacing.xl)

                // Events list
                if data.events.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.exclamationmark",
                        title: "No Events",
                        message: "No upcoming events from this source."
                    )
                } else {
                    LazyVStack(spacing: DS.Spacing.xl) {
                        ForEach(data.events) { event in
                            NavigationLink(value: EventDestination.event(slug: event.slug)) {
                                EventCardView(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                }
            }
        }
    }

    private func cityPicker(_ cities: [SourceCity]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.md) {
                // "All Cities" pill
                Button {
                    selectedCityId = nil
                } label: {
                    Text("All Cities")
                        .chipStyle(isSelected: selectedCityId == nil)
                }

                ForEach(cities) { city in
                    Button {
                        selectedCityId = city.id
                    } label: {
                        Text(city.name)
                            .chipStyle(isSelected: selectedCityId == city.id)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
        }
    }

    private func sourceHero(_ source: SourceInfo) -> some View {
        let theme = dsTheme(for: source.domains?.first)

        return ZStack(alignment: .bottomLeading) {
            // Gradient background
            theme.gradient
                .frame(height: DS.ImageSize.sourceBanner)

            // Content overlay
            HStack(spacing: DS.Spacing.lg) {
                if let logoUrl = source.logoUrl {
                    CachedImage(
                        url: URL(string: logoUrl),
                        height: DS.ImageSize.logoLarge,
                        cornerRadius: DS.Radius.lg,
                        placeholderIcon: "building.2",
                        contentMode: .fit
                    )
                    .frame(width: DS.ImageSize.logoLarge)
                    .dsShadow(DS.Shadow.subtle)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(source.name)
                        .font(DS.Typography.title)
                        .foregroundStyle(.primary)

                    if let count = source.eventCount {
                        Text("\(count) event\(count == 1 ? "" : "s")")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(DS.Spacing.lg)
            .glassBackground(cornerRadius: DS.Radius.lg)
            .padding(DS.Spacing.md)
        }
    }

    private func dsTheme(for domain: String?) -> DS.DomainTheme {
        switch domain {
        case "music", "concert": .music
        case "movies", "cinema", "screening": .cinema
        case "food": .food
        case "comedy": .comedy
        case "theater": .theater
        case "sports", "tournament": .sports
        case "trivia": .trivia
        case "festival": .festival
        default: .other
        }
    }

    private func loadSource() async {
        response = nil
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await APIClient.shared.fetchSourceDetail(slug: slug, cityId: selectedCityId)
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }
}
