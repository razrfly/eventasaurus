import SwiftUI

struct ContainerDetailView: View {
    let slug: String
    @State private var response: ContainerDetailResponse?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let response {
                containerContent(response)
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
        .task { await loadContainer() }
    }

    private func containerContent(_ data: ContainerDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Hero with overlaid title/type/dates
                if AppConfig.resolvedImageURL(data.container.coverImageUrl) != nil {
                    DramaticHero(
                        imageURL: AppConfig.resolvedImageURL(data.container.coverImageUrl),
                        placeholderIcon: "sparkles"
                    ) {
                        HeroOverlayCard {
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                Text(data.container.title)
                                    .font(DS.Typography.title)
                                    .foregroundStyle(.white)

                                HStack(spacing: DS.Spacing.md) {
                                    Text(data.container.containerType.capitalized)
                                        .font(DS.Typography.captionBold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, DS.Spacing.lg)
                                        .padding(.vertical, DS.Spacing.xs)
                                        .clearGlassBackground(cornerRadius: DS.Radius.full)

                                    if let start = data.container.startDate {
                                        if let end = data.container.endDate {
                                            Text("\(start, format: .dateTime.month(.abbreviated).day()) – \(end, format: .dateTime.month(.abbreviated).day())")
                                                .font(DS.Typography.body)
                                                .foregroundStyle(.white.opacity(0.9))
                                        } else {
                                            Text(start, format: .dateTime.month(.abbreviated).day())
                                                .font(DS.Typography.body)
                                                .foregroundStyle(.white.opacity(0.9))
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // No-image fallback: inline title
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(data.container.title)
                            .font(DS.Typography.title)

                        HStack(spacing: DS.Spacing.md) {
                            Text(data.container.containerType.capitalized)
                                .font(DS.Typography.captionBold)
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.xs)
                                .glassBackground(cornerRadius: DS.Radius.full)

                            if let start = data.container.startDate {
                                if let end = data.container.endDate {
                                    Text("\(start, format: .dateTime.month(.abbreviated).day()) – \(end, format: .dateTime.month(.abbreviated).day())")
                                        .font(DS.Typography.body)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(start, format: .dateTime.month(.abbreviated).day())
                                        .font(DS.Typography.body)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.top, DS.Spacing.xl)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Description
                    if let description = data.container.description, !description.isEmpty {
                        Text(description)
                            .font(DS.Typography.prose)
                    }

                    // Source link
                    if let sourceUrl = data.container.sourceUrl, let url = URL(string: sourceUrl) {
                        ExternalLinkButton(title: "View Source", url: url, icon: "arrow.up.right.square")
                    }

                    Divider()

                    // Events
                    if data.events.isEmpty {
                        EmptyStateView(
                            icon: "calendar.badge.exclamationmark",
                            title: "No Events",
                            message: "No events in this \(data.container.containerType)."
                        )
                    } else {
                        SectionHeader(
                            title: "Events",
                            subtitle: data.container.eventCount.map { "\($0) event\($0 == 1 ? "" : "s")" }
                        )

                        let grouped = groupEventsByDate(data.events)
                        LazyVStack(alignment: .leading, spacing: DS.Spacing.xl) {
                            ForEach(grouped, id: \.0) { dateKey, events in
                                Section {
                                    ForEach(events) { event in
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
                                                if let venue = event.venue {
                                                    Label(venue.displayName, systemImage: "mappin")
                                                        .font(DS.Typography.body)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } header: {
                                    Text(formatDateGroupHeader(dateKey))
                                        .font(DS.Typography.heading)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM d")
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return f
    }()

    private func groupEventsByDate(_ events: [Event]) -> [(String, [Event])] {
        var groups: [String: [Event]] = [:]

        for event in events {
            if let date = event.startsAt {
                let key = Self.isoDateFormatter.string(from: date)
                groups[key, default: []].append(event)
            } else {
                groups["TBD", default: []].append(event)
            }
        }

        return groups.sorted { a, b in
            if a.key == "TBD" { return false }
            if b.key == "TBD" { return true }
            return a.key < b.key
        }
    }

    private func formatDateGroupHeader(_ isoDate: String) -> String {
        if isoDate == "TBD" { return "Date TBD" }

        guard let date = Self.isoDateFormatter.date(from: isoDate) else { return isoDate }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today, \(Self.monthDayFormatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow, \(Self.monthDayFormatter.string(from: date))"
        } else {
            return Self.fullDateFormatter.string(from: date)
        }
    }

    private func loadContainer() async {
        do {
            response = try await APIClient.shared.fetchContainerDetail(slug: slug)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            self.error = error
            isLoading = false
        }
    }
}
