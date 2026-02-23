import Foundation

struct VenueDetailResponse: Codable {
    let venue: VenueInfo
    let events: [Event]
}

struct VenueInfo: Codable {
    let name: String?
    let slug: String?
    let address: String?
    let lat: Double?
    let lng: Double?
    let cityName: String?
    let country: String?
    let coverImageUrl: String?
    let eventCount: Int?

    var displayName: String {
        name ?? "Unknown Venue"
    }
}
