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
    var id: String { venue.name }
    let venue: ScreeningVenue
    let eventSlug: String
    let upcomingCount: Int
    let showtimes: [Showtime]
}

struct ScreeningVenue: Codable {
    let name: String
    let address: String?
}

struct Showtime: Codable, Identifiable {
    var id: String { datetime.description + (label ?? "") }
    let date: String
    let time: String?
    let label: String?
    let datetime: Date
    let isUpcoming: Bool
}
