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
    let status: String?
    let ticketUrl: String?
    let sources: [EventSource]?
    let nearbyEvents: [Event]?

    // Categories — API returns rich objects for list endpoints, strings for detail
    let categories: [Category]?

    /// Whether this item is an aggregated group (movie stack, event group, etc.)
    var isGroup: Bool {
        type == "movie_group" || type == "event_group" || type == "container_group"
    }

    /// Primary category (first in the list)
    var primaryCategory: Category? {
        categories?.first
    }

    /// Whether this event is upcoming (starts in the future)
    var isUpcoming: Bool {
        guard let startsAt else { return false }
        return startsAt > Date()
    }
}

// MARK: - Custom Decoder (handles categories as [Category] or [String])

extension Event {
    enum CodingKeys: String, CodingKey {
        case slug, title, startsAt, endsAt, coverImageUrl, type, venue
        case screeningCount, eventCount, venueCount, subtitle, containerType
        case description, attendeeCount, isAttending, status, categories
        case ticketUrl, sources, nearbyEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        type = try container.decode(String.self, forKey: .type)
        venue = try container.decodeIfPresent(Venue.self, forKey: .venue)
        screeningCount = try container.decodeIfPresent(Int.self, forKey: .screeningCount)
        eventCount = try container.decodeIfPresent(Int.self, forKey: .eventCount)
        venueCount = try container.decodeIfPresent(Int.self, forKey: .venueCount)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        containerType = try container.decodeIfPresent(String.self, forKey: .containerType)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        attendeeCount = try container.decodeIfPresent(Int.self, forKey: .attendeeCount)
        isAttending = try container.decodeIfPresent(Bool.self, forKey: .isAttending)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        ticketUrl = try container.decodeIfPresent(String.self, forKey: .ticketUrl)
        sources = try container.decodeIfPresent([EventSource].self, forKey: .sources)
        nearbyEvents = try container.decodeIfPresent([Event].self, forKey: .nearbyEvents)

        // Handle categories as either [Category] (rich objects) or [String] (detail endpoint)
        if let richCategories = try? container.decodeIfPresent([Category].self, forKey: .categories) {
            categories = richCategories
        } else if let stringCategories = try? container.decodeIfPresent([String].self, forKey: .categories) {
            categories = stringCategories.map {
                Category(numericId: nil, name: $0, slug: $0.slugified(), icon: nil, color: nil)
            }
        } else {
            categories = nil
        }
    }
}

struct EventSource: Codable, Identifiable {
    var id: String { name + (url ?? "") }
    let name: String
    let logoUrl: String?
    let url: String?
}

struct Venue: Codable {
    let name: String
    let slug: String?
    let address: String?
    let lat: Double?
    let lng: Double?
}

struct Meta: Codable {
    let page: Int?
    let perPage: Int?
    /// From attending endpoint
    let total: Int?
    /// From nearby endpoint
    let totalCount: Int?
    /// Total events across all date ranges
    let allEventsCount: Int?
    /// Per-date-range event counts for filter chips
    let dateRangeCounts: [String: Int]?

    /// Resolved total from whichever endpoint provided it
    var resolvedTotal: Int? {
        totalCount ?? total
    }
}
