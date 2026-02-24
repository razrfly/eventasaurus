import SwiftUI

struct MovieDetailView: View {
    let slug: String
    let cityId: Int?
    @State private var response: MovieDetailResponse?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var selectedDate: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let response {
                movieContent(response)
            } else if let error {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Error",
                    message: error.localizedDescription
                )
            }
        }
        .fullBleedNavigation()
        .task { await loadMovie() }
    }

    private func movieContent(_ data: MovieDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                // Hero: backdrop with poster overlay
                heroImage(data.movie)

                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // Rating pill (title+year now in hero overlay)
                    if let rating = data.movie.voteAverage {
                        HStack {
                            RatingPill(rating: rating)
                            Spacer()
                        }
                    }

                    // Tagline
                    if let tagline = data.movie.tagline {
                        Text(tagline)
                            .font(DS.Typography.bodyItalic)
                            .foregroundStyle(.secondary)
                    }

                    // Runtime + genres
                    HStack(spacing: DS.Spacing.lg) {
                        if let runtime = data.movie.runtime {
                            Label("\(runtime) min", systemImage: "clock")
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                        }

                        if !data.movie.genres.isEmpty {
                            Text(data.movie.genres.joined(separator: ", "))
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Overview
                    if let overview = data.movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(DS.Typography.prose)
                    }

                    // Cast
                    if let cast = data.movie.cast, !cast.isEmpty {
                        CastCarousel(cast: cast)
                    }

                    // External links
                    externalLinks(data.movie)

                    Divider()

                    // Screenings
                    if data.venues.isEmpty {
                        Text("No screenings found")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                    } else {
                        // Screenings header
                        SectionHeader(
                            title: "Screenings",
                            subtitle: "\(data.meta.totalShowtimes) at \(data.meta.totalVenues) venue\(data.meta.totalVenues == 1 ? "" : "s")"
                        )

                        // Day picker
                        dayPicker(venues: data.venues)

                        let filteredVenues = filteredVenues(data.venues)
                        ForEach(filteredVenues) { venueGroup in
                            venueCard(venueGroup)
                        }
                        .animation(DS.Animation.standard, value: selectedDate)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
        }
    }

    private func venueCard(_ venueGroup: VenueScreenings) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Venue header — links to venue detail page
            if let venueSlug = venueGroup.venue.slug {
                NavigationLink(value: EventDestination.venue(slug: venueSlug)) {
                    venueCardHeader(venueGroup, showChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                venueCardHeader(venueGroup, showChevron: false)
            }

            // Upcoming showtimes
            let upcoming = venueGroup.showtimes.filter(\.isUpcoming)
            let past = venueGroup.showtimes.filter { !$0.isUpcoming }

            if !upcoming.isEmpty {
                showtimesByDate(upcoming)
            }

            // Past showtimes (collapsed)
            if !past.isEmpty {
                if upcoming.isEmpty {
                    Text("Recently shown")
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(.secondary)
                    showtimesByDate(Array(past.suffix(10)))
                } else {
                    DisclosureGroup {
                        showtimesByDate(Array(past.suffix(10)))
                    } label: {
                        Text("\(past.count) past showtime\(past.count == 1 ? "" : "s")")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, DS.Spacing.md)
        .padding(.horizontal, DS.Spacing.lg)
        .glassBackground(cornerRadius: DS.Radius.lg)
        .accessibilityElement(children: .combine)
    }

    private func venueCardHeader(_ venueGroup: VenueScreenings, showChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack {
                Text(venueGroup.venue.displayName)
                    .font(DS.Typography.bodyBold)
                Spacer()
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let address = venueGroup.venue.address {
                Text(address)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func showtimesByDate(_ showtimes: [Showtime]) -> some View {
        let byDate = Dictionary(grouping: showtimes, by: \.date)
        let sortedDates = byDate.keys.sorted()
        return ForEach(sortedDates, id: \.self) { date in
            if let times = byDate[date] {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(formatDateHeader(date))
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: DS.Spacing.sm) {
                        ForEach(Array(times.enumerated()), id: \.offset) { _, showtime in
                            showtimePill(showtime)
                        }
                    }
                }
            }
        }
    }

    private func showtimePill(_ showtime: Showtime) -> some View {
        NavigationLink(value: EventDestination.event(slug: showtime.eventSlug ?? "")) {
            HStack(spacing: DS.Spacing.xs) {
                Text(showtime.datetime, format: .dateTime.hour().minute())
                    .font(DS.Typography.bodyBold)
                if let format = showtime.format {
                    Text(format.uppercased())
                        .font(DS.Typography.badge)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(formatColor(format).opacity(0.15))
                        .foregroundStyle(formatColor(format))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .glassBackground(cornerRadius: DS.Radius.md, interactive: showtime.isUpcoming)
            .opacity(showtime.isUpcoming ? 1.0 : 0.7)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    private func formatColor(_ format: String) -> Color {
        switch format.uppercased() {
        case "IMAX": return DS.Colors.info
        case "4DX", "3D": return DS.Colors.plan
        default: return .gray
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMM d")
        return f
    }()

    private func formatDateHeader(_ isoDate: String) -> String {
        guard let date = Self.isoDateFormatter.date(from: isoDate) else { return isoDate }
        return Self.displayDateFormatter.string(from: date)
    }

    // MARK: - Hero Image

    private func heroImage(_ movie: MovieInfo) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let backdropUrl = movie.backdropUrl {
                CachedImage(
                    url: URL(string: backdropUrl),
                    height: DS.ImageSize.heroMovie,
                    cornerRadius: 0,
                    placeholderIcon: "film"
                )
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.2), .black.opacity(DS.Opacity.heroGradient)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: DS.ImageSize.heroMovie * 3 / 4)
                }

                // Poster + title overlay
                HStack(alignment: .bottom, spacing: DS.Spacing.lg) {
                    if let posterUrl = movie.posterUrl {
                        CachedImage(
                            url: URL(string: posterUrl),
                            height: DS.ImageSize.posterOverlaySize.height,
                            cornerRadius: DS.Radius.md,
                            placeholderIcon: "film"
                        )
                        .frame(width: DS.ImageSize.posterOverlaySize.width)
                        .padding(DS.Spacing.xs)
                        .glassBackground(cornerRadius: DS.Radius.lg)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(movie.title)
                            .font(DS.Typography.title)
                            .foregroundStyle(.white)

                        if let releaseDate = movie.releaseDate,
                           let year = releaseDate.split(separator: "-").first {
                            Text("(\(year))")
                                .font(DS.Typography.titleSecondary)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.lg)
            } else if let posterUrl = movie.posterUrl {
                CachedImage(
                    url: URL(string: posterUrl),
                    height: DS.ImageSize.heroMovie,
                    cornerRadius: 0,
                    placeholderIcon: "film"
                )
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - External Links

    @ViewBuilder
    private func externalLinks(_ movie: MovieInfo) -> some View {
        let tmdbUrl = movie.tmdbId.flatMap { URL(string: "https://www.themoviedb.org/movie/\($0)") }
        let cinegraphUrl = movie.tmdbId.flatMap { URL(string: "https://cinegraph.org/movies/tmdb/\($0)") }

        if tmdbUrl != nil || cinegraphUrl != nil {
            HStack(spacing: DS.Spacing.lg) {
                if let url = tmdbUrl {
                    ExternalLinkButton(title: "TMDB", url: url, icon: "film")
                }
                if let url = cinegraphUrl {
                    ExternalLinkButton(title: "Cinegraph", url: url, icon: "popcorn")
                }
            }
        }
    }

    // MARK: - Day Picker

    private func dayPicker(venues: [VenueScreenings]) -> some View {
        let allDates = allUniqueDates(from: venues)
        let dateCounts = showtimeCountsByDate(from: venues)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.md) {
                // "All" pill
                dayPill(
                    label: "All",
                    count: venues.reduce(0) { $0 + $1.showtimes.count },
                    isSelected: selectedDate == nil
                ) {
                    withAnimation(DS.Animation.fast) {
                        selectedDate = nil
                    }
                }

                ForEach(allDates, id: \.self) { date in
                    dayPill(
                        label: formatDayPillLabel(date),
                        count: dateCounts[date] ?? 0,
                        isSelected: selectedDate == date
                    ) {
                        withAnimation(DS.Animation.fast) {
                            selectedDate = date
                        }
                    }
                }
            }
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    private func dayPill(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xxs) {
                Text(label)
                    .font(DS.Typography.captionBold)
                Text("\(count)")
                    .font(DS.Typography.micro)
                    .foregroundStyle(.secondary)
            }
            .glassChipStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count) showtimes")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func allUniqueDates(from venues: [VenueScreenings]) -> [String] {
        let dates = Set(venues.flatMap { $0.showtimes.map(\.date) })
        return dates.sorted()
    }

    private func showtimeCountsByDate(from venues: [VenueScreenings]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for venue in venues {
            for showtime in venue.showtimes {
                counts[showtime.date, default: 0] += 1
            }
        }
        return counts
    }

    private func filteredVenues(_ venues: [VenueScreenings]) -> [VenueScreenings] {
        guard let date = selectedDate else { return venues }
        return venues.compactMap { venue in
            let filtered = venue.showtimes.filter { $0.date == date }
            guard !filtered.isEmpty else { return nil }
            return VenueScreenings(
                venue: venue.venue,
                eventSlug: venue.eventSlug,
                upcomingCount: filtered.filter(\.isUpcoming).count,
                showtimes: filtered
            )
        }
    }

    private static let dayPillFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d")
        return f
    }()

    private func formatDayPillLabel(_ isoDate: String) -> String {
        guard let date = Self.isoDateFormatter.date(from: isoDate) else { return isoDate }
        return Self.dayPillFormatter.string(from: date).uppercased()
    }

    // MARK: - Data Loading

    private func loadMovie() async {
        do {
            response = try await APIClient.shared.fetchMovieDetail(slug: slug, cityId: cityId)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            self.error = error
            isLoading = false
        }
    }
}
