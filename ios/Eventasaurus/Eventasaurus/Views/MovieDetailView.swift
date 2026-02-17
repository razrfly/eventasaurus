import SwiftUI

struct MovieDetailView: View {
    let slug: String
    let cityId: Int?
    @State private var response: MovieDetailResponse?
    @State private var isLoading = true
    @State private var error: Error?

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
                // Backdrop image
                if let imageUrl = data.movie.backdropUrl ?? data.movie.posterUrl,
                   let url = URL(string: imageUrl) {
                    Color.clear
                        .frame(height: 220)
                        .overlay {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(.quaternary)
                            }
                        }
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 12) {
                    // Title + year
                    HStack(alignment: .firstTextBaseline) {
                        Text(data.movie.title)
                            .font(.title2.bold())

                        if let releaseDate = data.movie.releaseDate,
                           let year = releaseDate.split(separator: "-").first {
                            Text("(\(year))")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
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

                        ForEach(data.venues) { venueGroup in
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
        VStack(spacing: 2) {
            Text(showtime.datetime, format: .dateTime.hour().minute())
                .font(.subheadline.bold())
            if let label = showtime.label, !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
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

    private func loadMovie() async {
        defer { isLoading = false }
        do {
            response = try await APIClient.shared.fetchMovieDetail(slug: slug, cityId: cityId)
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }
}

// Simple flow layout for showtime pills
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
