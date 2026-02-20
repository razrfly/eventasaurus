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
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMovie() }
    }

    private func movieContent(_ data: MovieDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero: backdrop with poster overlay
                heroImage(data.movie)

                VStack(alignment: .leading, spacing: 12) {
                    // Title + year + rating
                    HStack(alignment: .firstTextBaseline) {
                        Text(data.movie.title)
                            .font(.title2.bold())

                        if let releaseDate = data.movie.releaseDate,
                           let year = releaseDate.split(separator: "-").first {
                            Text("(\(year))")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let rating = data.movie.voteAverage {
                            RatingPill(rating: rating)
                        }
                    }

                    // Tagline
                    if let tagline = data.movie.tagline {
                        Text(tagline)
                            .font(.subheadline.italic())
                            .foregroundStyle(.secondary)
                    }

                    // Runtime + genres
                    HStack(spacing: 12) {
                        if let runtime = data.movie.runtime {
                            Label("\(runtime) min", systemImage: "clock")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if !data.movie.genres.isEmpty {
                            Text(data.movie.genres.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Overview
                    if let overview = data.movie.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                    }

                    // Cast
                    if let cast = data.movie.cast, !cast.isEmpty {
                        CastCarousel(cast: cast)
                    }

                    // External links
                    externalLinks(data.movie)

                    Divider()

                    // Screenings header with count
                    if data.venues.isEmpty {
                        Text("No screenings found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Screenings")
                                .font(.headline)
                            Spacer()
                            Text("\(data.meta.totalShowtimes) showtime\(data.meta.totalShowtimes == 1 ? "" : "s") at \(data.meta.totalVenues) venue\(data.meta.totalVenues == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Day picker
                        dayPicker(venues: data.venues)

                        let filteredVenues = filteredVenues(data.venues)
                        ForEach(filteredVenues) { venueGroup in
                            venueCard(venueGroup)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func venueCard(_ venueGroup: VenueScreenings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Venue header — tapping navigates to the event detail
            NavigationLink(value: EventDestination.event(slug: venueGroup.eventSlug)) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(venueGroup.venue.name)
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let address = venueGroup.venue.address {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

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
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    showtimesByDate(Array(past.suffix(10)))
                } else {
                    DisclosureGroup {
                        showtimesByDate(Array(past.suffix(10)))
                    } label: {
                        Text("\(past.count) past showtime\(past.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func showtimesByDate(_ showtimes: [Showtime]) -> some View {
        let byDate = Dictionary(grouping: showtimes, by: \.date)
        let sortedDates = byDate.keys.sorted()
        return ForEach(sortedDates, id: \.self) { date in
            if let times = byDate[date] {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDateHeader(date))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(Array(times.enumerated()), id: \.offset) { _, showtime in
                            showtimePill(showtime)
                        }
                    }
                }
            }
        }
    }

    private func showtimePill(_ showtime: Showtime) -> some View {
        HStack(spacing: 4) {
            Text(showtime.datetime, format: .dateTime.hour().minute())
                .font(.subheadline.bold())
            if let format = showtime.format {
                Text(format.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(formatColor(format).opacity(0.15))
                    .foregroundStyle(formatColor(format))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(showtime.isUpcoming ? Color.accentColor.opacity(0.1) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(showtime.isUpcoming ? Color.accentColor.opacity(0.3) : Color(.systemGray4), lineWidth: 0.5)
        )
    }

    private func formatColor(_ format: String) -> Color {
        switch format.uppercased() {
        case "IMAX": return .blue
        case "4DX", "3D": return .purple
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
        f.dateFormat = "EEEE, MMM d"
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
                    height: 220,
                    cornerRadius: 0,
                    placeholderIcon: "film"
                )

                // Poster overlay (only when both exist)
                if let posterUrl = movie.posterUrl {
                    CachedImage(
                        url: URL(string: posterUrl),
                        height: 120,
                        cornerRadius: 8,
                        placeholderIcon: "film"
                    )
                    .frame(width: 80)
                    .shadow(radius: 4)
                    .padding(.leading, 16)
                    .padding(.bottom, -20)
                }
            } else if let posterUrl = movie.posterUrl {
                CachedImage(
                    url: URL(string: posterUrl),
                    height: 220,
                    cornerRadius: 0,
                    placeholderIcon: "film"
                )
            }
        }
        .clipped()
    }

    // MARK: - External Links

    @ViewBuilder
    private func externalLinks(_ movie: MovieInfo) -> some View {
        let tmdbUrl = movie.tmdbId.flatMap { URL(string: "https://www.themoviedb.org/movie/\($0)") }
        let cinegraphUrl = movie.tmdbId.flatMap { URL(string: "https://cinegraph.org/movies/tmdb/\($0)") }

        if tmdbUrl != nil || cinegraphUrl != nil {
            HStack(spacing: 12) {
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
            HStack(spacing: 8) {
                // "All" pill
                dayPill(
                    label: "All",
                    count: venues.reduce(0) { $0 + $1.showtimes.count },
                    isSelected: selectedDate == nil
                ) {
                    selectedDate = nil
                }

                ForEach(allDates, id: \.self) { date in
                    dayPill(
                        label: formatDayPillLabel(date),
                        count: dateCounts[date] ?? 0,
                        isSelected: selectedDate == date
                    ) {
                        selectedDate = date
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func dayPill(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption.bold())
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
        f.dateFormat = "EEE d"
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
