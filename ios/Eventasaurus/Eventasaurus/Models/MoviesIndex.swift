import Foundation

struct MoviesIndexResponse: Codable {
    let movies: [MovieListItem]
    let stats: MovieStats
    let cities: [MovieCity]
}

struct MovieListItem: Codable, Identifiable {
    var id: String { slug }
    let slug: String
    let title: String
    let posterUrl: String?
    let releaseDate: String?
    let runtime: Int?
    let genres: [String]?
    let voteAverage: Double?
    let cityCount: Int
    let screeningCount: Int
    let nextScreening: Date?
}

struct MovieStats: Codable {
    let movieCount: Int
    let screeningCount: Int
    let cityCount: Int
}

struct MovieCity: Codable, Identifiable {
    var id: String { slug }
    let name: String
    let slug: String
    let movieCount: Int
    let screeningCount: Int
}
