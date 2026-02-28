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
                    // Ratings row
                    ratingsRow(data.movie)

                    // Tagline
                    if let tagline = data.movie.tagline {
                        Text(tagline)
                            .font(DS.Typography.bodyItalic)
                            .foregroundStyle(.secondary)
                    }

                    // Runtime + genres + director
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

                        if let director = data.movie.cinegraph?.director {
                            Label(director, systemImage: "video.fill")
                                .font(DS.Typography.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Awards row
                    if let awards = awardsRow(data.movie) {
                        awards
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
        .ignoresSafeArea(edges: .top)
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

    // MARK: - Ratings Row

    @ViewBuilder
    private func ratingsRow(_ movie: MovieInfo) -> some View {
        if let ratings = movie.cinegraph?.ratings {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                if let tmdb = ratings.tmdb {
                    Text("⭐ \(String(format: "%.1f", tmdb)) TMDB")
                        .font(DS.Typography.badge)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(Color.blue.opacity(DS.Opacity.tintedBackground))
                        .foregroundStyle(Color.blue)
                        .clipShape(Capsule())
                }
                if let imdb = ratings.imdb {
                    let amberColor = Color(red: 0.5, green: 0.35, blue: 0.0)
                    Text("🎬 \(String(format: "%.1f", imdb)) IMDb")
                        .font(DS.Typography.badge)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(Color.yellow.opacity(DS.Opacity.tintedBackground))
                        .foregroundStyle(amberColor)
                        .clipShape(Capsule())
                }
                if let rt = ratings.rottenTomatoes {
                    let icon = rt >= 60 ? "🍅" : "🦠"
                    let color = rtBadgeColor(rt)
                    Text("\(icon) \(rt)% RT")
                        .font(DS.Typography.badge)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(color.opacity(DS.Opacity.tintedBackground))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
                if let mc = ratings.metacritic {
                    let color = metacriticBadgeColor(mc)
                    Text("📰 \(mc) MC")
                        .font(DS.Typography.badge)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(color.opacity(DS.Opacity.tintedBackground))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
            }
            }
        } else if let rating = movie.voteAverage {
            HStack {
                RatingPill(rating: rating)
                Spacer()
            }
        }
    }

    private func rtBadgeColor(_ score: Int) -> Color {
        if score >= 75 { return .green }
        if score >= 60 { return Color(red: 0.6, green: 0.8, blue: 0.0) }
        return .red
    }

    private func metacriticBadgeColor(_ score: Int) -> Color {
        if score >= 61 { return .green }
        if score >= 40 { return .orange }
        return .red
    }

    // MARK: - Awards Row

    private func awardsRow(_ movie: MovieInfo) -> AwardsRowView? {
        guard let awards = movie.cinegraph?.awards else { return nil }
        let hasOscars = (awards.oscarWins ?? 0) > 0
        let hasSummary = !(awards.summary ?? "").isEmpty
        let hasWins = (awards.totalWins ?? 0) > 0
        let hasNoms = (awards.totalNominations ?? 0) > 0
        guard hasOscars || hasSummary || hasWins || hasNoms else { return nil }
        return AwardsRowView(awards: awards)
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

        HStack(spacing: DS.Spacing.lg) {
            // Cinegraph — only show when cinegraph data is available
            if movie.cinegraph != nil {
                NavigationLink {
                    CinegraphDetailView(movie: movie)
                } label: {
                    Label("Cinegraph", systemImage: "popcorn")
                        .font(DS.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassSecondary)
            }

            // TMDB — external link, only when tmdbId exists
            if let url = tmdbUrl {
                ExternalLinkButton(title: "TMDB", url: url, icon: "film")
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

// MARK: - Awards Row View

struct AwardsRowView: View {
    let awards: CinegraphAwards

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let wins = awards.oscarWins, wins > 0 {
                Text("🏆 \(wins) Oscar Win\(wins == 1 ? "" : "s")")
                    .font(DS.Typography.badge)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(Color.yellow.opacity(DS.Opacity.tintedBackground))
                    .foregroundStyle(Color(red: 0.6, green: 0.4, blue: 0.0))
                    .clipShape(Capsule())
            }

            if let summaryText = awardsSummaryText() {
                Text(summaryText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func awardsSummaryText() -> String? {
        if let summary = awards.summary, !summary.isEmpty {
            return summary
        }
        let wins = awards.totalWins ?? 0
        let noms = awards.totalNominations ?? 0
        if wins > 0 && noms > 0 {
            return "\(wins) wins & \(noms) nominations"
        } else if wins > 0 {
            return "\(wins) wins"
        } else if noms > 0 {
            return "\(noms) nominations"
        }
        return nil
    }
}
