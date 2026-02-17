import Foundation

struct CitiesResponse: Codable {
    let cities: [City]
}

struct City: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let latitude: Double?
    let longitude: Double?
    let timezone: String?
    let country: String?
}
