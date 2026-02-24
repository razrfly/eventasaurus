import Foundation

struct EventsResponse: Codable {
    let events: [Event]
    let meta: Meta
}

struct EventDetailResponse: Codable {
    let event: Event
}

struct Event: Codable, Identifiable, Hashable {

    func hash(into hasher: inout Hasher) {
        hasher.combine(slug)
    }

    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.slug == rhs.slug
    }

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

    // Movie group metadata (from TMDB)
    let runtime: Int?
    let voteAverage: Double?
    let genres: [String]?
    let tagline: String?

    // Detail-only fields
    let description: String?
    let attendeeCount: Int?
    let isAttending: Bool?
    let attendanceStatus: String?
    let status: String?
    let ticketUrl: String?
    let sources: [EventSource]?
    let nearbyEvents: [Event]?

    // Categories — API returns rich objects for list endpoints, strings for detail
    let categories: [Category]?

    /// Whether this item is a movie group (aggregated screenings across venues).
    var isMovieGroup: Bool { type == "movie_group" }

    /// Whether this item is an aggregated group (movie stack, event group, etc.)
    var isGroup: Bool {
        isMovieGroup || type == "event_group" || type == "container_group"
    }

    /// Whether this movie group has usable TMDB metadata (rating, runtime, or genres).
    var hasTmdbData: Bool {
        guard isMovieGroup else { return false }
        return (voteAverage ?? 0) > 0 || (runtime ?? 0) >= 30 || !(genres ?? []).isEmpty
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

    /// Time-based badge text for events starting soon/today/tomorrow.
    /// - Parameter compact: When true, uses shorter text (e.g. "Soon" vs "Starting soon")
    func timeBadgeText(compact: Bool = false) -> String? {
        guard let startsAt, !isGroup else { return nil }
        let interval = startsAt.timeIntervalSince(Date())
        if interval < 0 { return nil }
        if interval < 3600 { return compact ? String(localized: "Soon") : String(localized: "Starting soon") }
        if Calendar.current.isDateInToday(startsAt) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(startsAt) { return String(localized: "Tomorrow") }
        return nil
    }
}

// MARK: - Custom Decoder (handles categories as [Category] or [String])

extension Event {
    enum CodingKeys: String, CodingKey {
        case slug, title, startsAt, endsAt, coverImageUrl, type, venue
        case screeningCount, eventCount, venueCount, subtitle, containerType
        case runtime, voteAverage, genres, tagline
        case description, attendeeCount, isAttending, attendanceStatus, status, categories
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
        runtime = try container.decodeIfPresent(Int.self, forKey: .runtime)
        voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage)
        genres = try container.decodeIfPresent([String].self, forKey: .genres)
        tagline = try container.decodeIfPresent(String.self, forKey: .tagline)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        attendeeCount = try container.decodeIfPresent(Int.self, forKey: .attendeeCount)
        isAttending = try container.decodeIfPresent(Bool.self, forKey: .isAttending)
        attendanceStatus = try container.decodeIfPresent(String.self, forKey: .attendanceStatus)
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
    let id: String
    let name: String?
    let logoUrl: String?
    let url: String?

    var displayName: String {
        name ?? "Unknown Source"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, logoUrl, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        logoUrl = try container.decodeIfPresent(String.self, forKey: .logoUrl)
        url = try container.decodeIfPresent(String.self, forKey: .url)

        if let apiId = try container.decodeIfPresent(String.self, forKey: .id), !apiId.isEmpty {
            id = apiId
        } else if let url, !url.isEmpty {
            id = url
        } else if let name, !name.isEmpty {
            id = name
        } else {
            // Deterministic fallback: derive from stable fields so repeated decodes
            // produce the same identity instead of a random UUID each time.
            // In this branch url and name are guaranteed nil or empty, so only
            // logoUrl can contribute meaningful data.
            let stableKey = [url, name, logoUrl]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: "|")
            if stableKey.isEmpty {
                id = "source_unknown"
            } else {
                // FNV-1a 64-bit hash — deterministic across process launches
                // (unlike Swift.Hasher which is seeded per-process).
                var hash: UInt64 = 14695981039346656037
                for byte in stableKey.utf8 {
                    hash ^= UInt64(byte)
                    hash &*= 1099511628211
                }
                id = "source_\(hash)"
            }
        }
    }
}

// MARK: - EventDisplayable

extension Event: EventDisplayable {
    var displaySlug: String { slug }
    var displayTitle: String { title }
    var displayTagline: String? { subtitle }
    var displayStartsAt: Date? { startsAt }
    var displayEndsAt: Date? { endsAt }
    var displayCoverImageUrl: String? { coverImageUrl }
    var displayVenueName: String? { venue?.displayName }
    var displayIsVirtual: Bool { false }
    var displayParticipantCount: Int? { attendeeCount }
    var displayPrimaryCategoryIcon: String? { primaryCategory?.icon }
    var displayPrimaryCategoryName: String? { primaryCategory?.name }

    var displayCompactMetadata: String? {
        guard isGroup else { return nil }

        // Movie groups with TMDB data: view renders SF Symbol metadata instead
        if isMovieGroup {
            if hasTmdbData { return nil }
            // No TMDB data — fall back to tagline or counts
            if let tag = tagline, !tag.isEmpty { return tag }
            return showtimeVenueSummary ?? subtitle
        }

        var parts: [String] = []
        if type == "event_group", let count = eventCount, count > 0 {
            parts.append("\(count) event\(count == 1 ? "" : "s")")
        }
        if let count = venueCount, count > 0 {
            parts.append("at \(count) venue\(count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? subtitle : parts.joined(separator: " · ")
    }

    // MARK: - Movie TMDB Properties

    var displayMovieRating: Double? {
        guard isMovieGroup, let rating = voteAverage, rating > 0 else { return nil }
        return rating
    }

    var displayMovieRuntime: Int? {
        guard isMovieGroup, let mins = runtime, mins >= 30 else { return nil }
        return mins
    }

    var displayMovieGenres: String? {
        guard isMovieGroup, let movieGenres = genres, !movieGenres.isEmpty else { return nil }
        return movieGenres.prefix(2).joined(separator: ", ")
    }

    /// Secondary line for movie groups: tagline if available, otherwise screening counts
    /// when TMDB metadata is already shown as the primary line.
    var displayCompactTagline: String? {
        guard isMovieGroup, hasTmdbData else { return nil }
        if let tag = tagline, !tag.isEmpty { return tag }
        return showtimeVenueSummary
    }

    /// Showtime/venue count summary (e.g. "3 showtimes · at 3 venues"). Reused by
    /// `displayCompactMetadata` (fallback) and `displayCompactTagline` (secondary line).
    private var showtimeVenueSummary: String? {
        var parts: [String] = []
        if let count = screeningCount, count > 0 {
            parts.append("\(count) showtime\(count == 1 ? "" : "s")")
        }
        if let count = venueCount, count > 0 {
            parts.append("at \(count) venue\(count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct Venue: Codable, Hashable {
    let name: String?
    let slug: String?
    let address: String?
    let lat: Double?
    let lng: Double?

    var displayName: String {
        name ?? "Unknown Venue"
    }
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
