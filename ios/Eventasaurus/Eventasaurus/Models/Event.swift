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

    // Aggregated group fields
    let screeningCount: Int?
    let eventCount: Int?
    let venueCount: Int?
    let subtitle: String?
    let containerType: String?

    // Detail-only fields
    let description: String?
    let attendeeCount: Int?
    let isAttending: Bool?
    let categories: [String]?
    let status: String?

    /// Whether this item is an aggregated group (movie stack, event group, etc.)
    var isGroup: Bool {
        type == "movie_group" || type == "event_group" || type == "container_group"
    }
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
    let totalCount: Int?
}
