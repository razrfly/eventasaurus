import Foundation

struct CitiesResponse: Codable {
    let cities: [City]
}

struct CityResolveResponse: Codable {
    let city: City
}

struct City: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let latitude: Double?
    let longitude: Double?
    let timezone: String?
    let country: String?
    let countryCode: String?
    let eventCount: Int?
}
