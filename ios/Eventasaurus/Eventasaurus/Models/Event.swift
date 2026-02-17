import Foundation

struct EventsResponse: Codable {
    let events: [Event]
    let meta: Meta
}

struct EventDetailResponse: Codable {
    let event: Event
}

struct Event: Codable, Identifiable {
    var id: String { slug }
    let slug: String
    let title: String
    let startsAt: Date?
    let endsAt: Date?
    let coverImageUrl: String?
    let type: String
    let venue: Venue?

    // Detail-only fields
    let description: String?
    let attendeeCount: Int?
    let isAttending: Bool?
    let categories: [String]?
    let status: String?
}

struct Venue: Codable {
    let name: String
    let address: String?
    let lat: Double?
    let lng: Double?
}

struct Meta: Codable {
    let page: Int?
    let perPage: Int?
    let total: Int?
}
