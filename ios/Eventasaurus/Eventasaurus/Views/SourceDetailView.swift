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
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
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
            VStack(alignment: .leading, spacing: 16) {
                // Themed hero card
                sourceHero(data.source)

                // Website link
                if let websiteUrl = data.source.websiteUrl, let url = URL(string: websiteUrl) {
                    ExternalLinkButton(title: "Visit Website", url: url, icon: "globe")
                        .padding(.horizontal)
                }

                // City filter pills
                if let cities = data.availableCities, cities.count > 1 {
                    cityPicker(cities)
                }

                Divider()
                    .padding(.horizontal)

                // Events list
                if data.events.isEmpty {
                    ContentUnavailableView {
                        Label("No Events", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("No upcoming events from this source.")
                    }
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(data.events) { event in
                            NavigationLink(value: EventDestination.event(slug: event.slug)) {
                                EventCardView(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func cityPicker(_ cities: [SourceCity]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All Cities" pill
                Button {
                    selectedCityId = nil
                } label: {
                    Text("All Cities")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(selectedCityId == nil ? Color.accentColor : Color(.systemGray5))
                        .foregroundStyle(selectedCityId == nil ? .white : .primary)
                        .clipShape(Capsule())
                }

                ForEach(cities) { city in
                    Button {
                        selectedCityId = city.id
                    } label: {
                        Text(city.name)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedCityId == city.id ? Color.accentColor : Color(.systemGray5))
                            .foregroundStyle(selectedCityId == city.id ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func sourceHero(_ source: SourceInfo) -> some View {
        let theme = domainTheme(for: source.domains?.first)

        return ZStack(alignment: .bottomLeading) {
            // Gradient background
            LinearGradient(
                colors: theme.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 180)

            // Content overlay
            HStack(spacing: 12) {
                if let logoUrl = source.logoUrl {
                    CachedImage(
                        url: URL(string: logoUrl),
                        height: 56,
                        cornerRadius: 12,
                        placeholderIcon: "building.2",
                        contentMode: .fit
                    )
                    .frame(width: 56)
                    .shadow(radius: 4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    if let count = source.eventCount {
                        Text("\(count) event\(count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    private struct DomainTheme {
        let colors: [Color]
    }

    private func domainTheme(for domain: String?) -> DomainTheme {
        switch domain {
        case "music", "concert":
            return DomainTheme(colors: [.blue, .blue.opacity(0.7)])
        case "movies", "cinema", "screening":
            return DomainTheme(colors: [.indigo, .indigo.opacity(0.7)])
        case "food":
            return DomainTheme(colors: [.orange, .orange.opacity(0.7)])
        case "comedy":
            return DomainTheme(colors: [.orange, .orange.opacity(0.8)])
        case "theater":
            return DomainTheme(colors: [.red, .red.opacity(0.7)])
        case "sports", "tournament":
            return DomainTheme(colors: [.green, .green.opacity(0.7)])
        case "trivia":
            return DomainTheme(colors: [.purple, .purple.opacity(0.7)])
        case "festival":
            return DomainTheme(colors: [.pink, .pink.opacity(0.7)])
        default:
            return DomainTheme(colors: [Color(.systemGray), Color(.systemGray2)])
        }
    }

    private func loadSource() async {
        isLoading = true
        do {
            response = try await APIClient.shared.fetchSourceDetail(slug: slug, cityId: selectedCityId)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            self.error = error
            isLoading = false
        }
    }
}
