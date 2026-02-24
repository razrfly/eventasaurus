import Foundation

/// Wrapper that silently skips elements that fail to decode in arrays.
/// Usage: `[SafeDecodable<MyType>].compactMap(\.value)`
struct SafeDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct EventsResponse: Decodable {
    let events: [Event]
    let meta: Meta
}

struct EventDetailResponse: Decodable {
    let event: Event
}

struct Event: Decodable, Identifiable, Hashable {

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

    // Categories — API returns rich objects for list endpoints, strings for detail
    let categories: [Category]?

    // Detail-only fields stored on the heap to keep Event small enough for
    // SwiftUI's deeply nested view builder copies (prevents stack overflow).
    private let _detail: _DetailStorage?

    var description: String? { _detail?.description }
    var attendeeCount: Int? { _detail?.attendeeCount }
    var isAttending: Bool? { _detail?.isAttending }
    var attendanceStatus: String? { _detail?.attendanceStatus }
    var status: String? { _detail?.status }
    var ticketUrl: String? { _detail?.ticketUrl }
    var sources: [EventSource]? { _detail?.sources }
    var nearbyEvents: [Event]? { _detail?.nearbyEvents }
    var movieGroupSlug: String? { _detail?.movieGroupSlug }
    var movieCityId: Int? { _detail?.movieCityId }
    var occurrences: EventOccurrences? { _detail?.occurrences }

    /// Whether this item is a movie group (aggregated screenings across venues).
    var isMovieGroup: Bool { type == "movie_group" }

    /// Whether this event is a movie screening (has showtimes in occurrences).
    var isMovieScreening: Bool { movieGroupSlug != nil && occurrences?.dates?.isEmpty == false }

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

// MARK: - Detail Storage (heap-allocated to keep Event struct small)

extension Event {
    /// Heap-allocated storage for fields only used in detail views.
    /// Reduces Event's inline size so SwiftUI view builders don't overflow the stack
    /// when copying Event through deeply nested generic type chains.
    final class _DetailStorage {
        let description: String?
        let attendeeCount: Int?
        let isAttending: Bool?
        let attendanceStatus: String?
        let status: String?
        let ticketUrl: String?
        let sources: [EventSource]?
        let nearbyEvents: [Event]?
        let movieGroupSlug: String?
        let movieCityId: Int?
        let occurrences: EventOccurrences?

        init(
            description: String?, attendeeCount: Int?, isAttending: Bool?,
            attendanceStatus: String?, status: String?, ticketUrl: String?,
            sources: [EventSource]?, nearbyEvents: [Event]?,
            movieGroupSlug: String?, movieCityId: Int?, occurrences: EventOccurrences?
        ) {
            self.description = description
            self.attendeeCount = attendeeCount
            self.isAttending = isAttending
            self.attendanceStatus = attendanceStatus
            self.status = status
            self.ticketUrl = ticketUrl
            self.sources = sources
            self.nearbyEvents = nearbyEvents
            self.movieGroupSlug = movieGroupSlug
            self.movieCityId = movieCityId
            self.occurrences = occurrences
        }
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
        case movieGroupSlug, movieCityId, occurrences
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

        // Decode detail-only fields into heap-allocated storage
        let desc = try container.decodeIfPresent(String.self, forKey: .description)
        let attCount = try container.decodeIfPresent(Int.self, forKey: .attendeeCount)
        let isAtt = try container.decodeIfPresent(Bool.self, forKey: .isAttending)
        let attStatus = try container.decodeIfPresent(String.self, forKey: .attendanceStatus)
        let stat = try container.decodeIfPresent(String.self, forKey: .status)
        let ticket = try container.decodeIfPresent(String.self, forKey: .ticketUrl)
        let srcs = try container.decodeIfPresent([EventSource].self, forKey: .sources)
        let mgSlug = try container.decodeIfPresent(String.self, forKey: .movieGroupSlug)
        let mgCity = try container.decodeIfPresent(Int.self, forKey: .movieCityId)
        let occ = try container.decodeIfPresent(EventOccurrences.self, forKey: .occurrences)

        // Decode nearbyEvents resiliently — skip individual events that fail
        let nearby: [Event]?
        if let rawNearby = try? container.decodeIfPresent([SafeDecodable<Event>].self, forKey: .nearbyEvents) {
            nearby = rawNearby.compactMap(\.value)
        } else {
            nearby = nil
        }

        // Only allocate detail storage if any detail field is non-nil
        let hasDetail = desc != nil || attCount != nil || isAtt != nil || attStatus != nil
            || stat != nil || ticket != nil || srcs != nil || nearby != nil
            || mgSlug != nil || mgCity != nil || occ != nil
        _detail = hasDetail ? _DetailStorage(
            description: desc, attendeeCount: attCount, isAttending: isAtt,
            attendanceStatus: attStatus, status: stat, ticketUrl: ticket,
            sources: srcs, nearbyEvents: nearby,
            movieGroupSlug: mgSlug, movieCityId: mgCity, occurrences: occ
        ) : nil
    }
}

// MARK: - Occurrences (Screening Schedule)

struct EventOccurrences: Codable {
    let dates: [EventShowtime]?
}

struct EventShowtime: Codable, Identifiable {
    var id: String { "\(date)_\(time ?? "")_\(label ?? "")" }
    let date: String
    let time: String?
    let label: String?
    let externalId: String?

    /// Extract format from label (e.g., "IMAX 2D Napisy PL" → "IMAX", "2D Dubbed" → "2D")
    var format: String? {
        guard let label else { return nil }
        let upper = label.uppercased()
        if upper.contains("IMAX") { return "IMAX" }
        if upper.contains("4DX") { return "4DX" }
        if upper.contains("3D") { return "3D" }
        if upper.contains("2D") { return "2D" }
        return nil
    }

    /// Whether this showtime is in the future
    var isUpcoming: Bool {
        guard let time else { return false }
        let isoString = "\(date)T\(time):00"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        guard let dt = formatter.date(from: isoString) else { return false }
        return dt > Date()
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
