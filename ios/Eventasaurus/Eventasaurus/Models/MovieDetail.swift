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
    let voteAverage: Double?
    let tagline: String?
    let cast: [CastMember]?
    let tmdbId: Int?
    let imdbId: String?
}

struct CastMember: Codable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profileUrl: String?
}

struct VenueScreenings: Codable, Identifiable {
    var id: String { eventSlug }
    let venue: ScreeningVenue
    let eventSlug: String
    let upcomingCount: Int
    let showtimes: [Showtime]
}

struct ScreeningVenue: Codable {
    let name: String?
    let address: String?
    let lat: Double?
    let lng: Double?

    var displayName: String {
        name ?? "Unknown Venue"
    }
}

struct Showtime: Codable {
    let date: String
    let time: String?
    let label: String?
    let format: String?
    let datetime: Date
    let isUpcoming: Bool
}

