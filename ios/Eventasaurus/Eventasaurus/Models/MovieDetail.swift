import Foundation

struct MovieDetailResponse: Codable {
    let movie: MovieInfo
    let venues: [VenueScreenings]
    let meta: MovieMeta
}

struct MovieMeta: Codable {
    let totalVenues: Int
    let totalShowtimes: Int
}

struct MovieInfo: Codable {
    let title: String
    let slug: String
    let overview: String?
    let posterUrl: String?
    let backdropUrl: String?
    let releaseDate: String?
    let runtime: Int?
    let genres: [String]
}

struct VenueScreenings: Codable, Identifiable {
    var id: String { eventSlug }
    let venue: ScreeningVenue
    let eventSlug: String
    let upcomingCount: Int
    let showtimes: [Showtime]

    var indexedShowtimes: [IndexedShowtime] {
        showtimes.enumerated().map { IndexedShowtime(index: $0.offset, showtime: $0.element, venueSlug: eventSlug) }
    }
}

struct ScreeningVenue: Codable {
    let name: String
    let address: String?
}

struct Showtime: Codable {
    let date: String
    let time: String?
    let label: String?
    let datetime: Date
    let isUpcoming: Bool
}

struct IndexedShowtime: Identifiable {
    var id: String { "\(venueSlug)-\(index)" }
    let index: Int
    let showtime: Showtime
    let venueSlug: String
}
