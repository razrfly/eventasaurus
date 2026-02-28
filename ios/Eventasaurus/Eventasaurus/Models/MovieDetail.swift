import CryptoKit
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
    let cinegraph: CinegraphInfo?
}

struct CastMember: Codable, Identifiable {
    let name: String
    let character: String?
    let order: Int?
    let profileUrl: String?

    // Collision-resistant ID: SHA256 of a JSON-encoded payload covering all fields.
    // JSONEncoder preserves nil (→ null) vs empty string (""), and escapes any
    // special characters in values, so the encoding is injective and unambiguous.
    var id: String {
        struct Payload: Encodable {
            let order: Int?
            let name: String
            let character: String?
            let profileUrl: String?
        }
        let payload = Payload(order: order, name: name, character: character, profileUrl: profileUrl)
        let data = (try? JSONEncoder().encode(payload)) ?? Data(name.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
}

struct VenueScreenings: Codable, Identifiable {
    var id: String { eventSlug }
    let venue: ScreeningVenue
    let eventSlug: String
    let upcomingCount: Int
    let showtimes: [Showtime]
}

struct ScreeningVenue: Codable, Identifiable {
    let name: String?
    let slug: String?
    let address: String?
    let lat: Double?
    let lng: Double?

    // Stable in-memory unique ID (not persisted via Codable)
    private let _uuid = UUID()

    var id: String {
        if let slug, !slug.isEmpty { return slug }
        if let name, !name.isEmpty { return name }
        return "\(displayName)_\(_uuid.uuidString)"
    }

    var displayName: String {
        name ?? "Unknown Venue"
    }

    enum CodingKeys: String, CodingKey {
        case name, slug, address, lat, lng
    }
}

struct Showtime: Codable {
    let date: String
    let time: String?
    let label: String?
    let format: String?
    let datetime: Date
    let isUpcoming: Bool
    let eventSlug: String?
}

struct CinegraphInfo: Codable {
    let ratings: CinegraphRatings?
    let director: String?
    let awards: CinegraphAwards?
    let cinegraphSlug: String?
}

struct CinegraphRatings: Codable {
    let imdb: Double?
    let rottenTomatoes: Int?
    let metacritic: Int?
    let tmdb: Double?
}

struct CinegraphAwards: Codable {
    let oscarWins: Int?
    let totalWins: Int?
    let totalNominations: Int?
    let summary: String?
}

