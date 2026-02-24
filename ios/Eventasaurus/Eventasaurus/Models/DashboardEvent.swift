import Foundation

// MARK: - Dashboard Filters

enum DashboardTimeFilter: String {
    case upcoming = "UPCOMING"
    case past = "PAST"
    case archived = "ARCHIVED"
}

enum DashboardOwnershipFilter: String {
    case all = "ALL"
    case created = "CREATED"
    case participating = "PARTICIPATING"
}

// MARK: - Dashboard Event Model

struct DashboardEvent: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String
    let tagline: String?
    let description: String?
    let startsAt: Date?
    let endsAt: Date?
    let timezone: String?
    let status: EventStatus
    let coverImageUrl: String?
    let isVirtual: Bool
    let userRole: String
    let userStatus: String?
    let canManage: Bool
    let participantCount: Int
    let venue: DashboardVenue?
    let createdAt: Date?
    let updatedAt: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(slug)
    }

    static func == (lhs: DashboardEvent, rhs: DashboardEvent) -> Bool {
        lhs.slug == rhs.slug
    }
}

// MARK: - Dashboard Venue

struct DashboardVenue: Codable, Hashable {
    let id: String
    let name: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

// MARK: - Dashboard Role

enum DashboardRole {
    case hosting
    case going
    case pending
    case notGoing

    var displayName: String {
        switch self {
        case .hosting: return "Hosting"
        case .going: return "Going"
        case .pending: return "Pending"
        case .notGoing: return "Not Going"
        }
    }
}

extension DashboardEvent {
    var role: DashboardRole {
        if userRole == "organizer" {
            return .hosting
        }
        switch userStatus {
        case "accepted", "confirmed", "confirmed_with_order":
            return .going
        case "interested", "pending":
            return .pending
        case "declined":
            return .notGoing
        default:
            return .notGoing
        }
    }
}

// MARK: - EventDisplayable

extension DashboardEvent: EventDisplayable {
    var displaySlug: String { slug }
    var displayTitle: String { title }
    var displayTagline: String? { tagline }
    var displayStartsAt: Date? { startsAt }
    var displayEndsAt: Date? { endsAt }
    var displayCoverImageUrl: String? { coverImageUrl }
    var displayVenueName: String? { isVirtual ? "Online" : venue?.name }
    var displayIsVirtual: Bool { isVirtual }
    var displayParticipantCount: Int? { participantCount > 0 ? participantCount : nil }
}

// MARK: - Filter Counts

struct DashboardFilterCounts: Codable {
    let upcoming: Int
    let past: Int
    let archived: Int
    let created: Int
    let participating: Int
}

// MARK: - Combined Result

struct DashboardEventsResult: Codable {
    let events: [DashboardEvent]
    let filterCounts: DashboardFilterCounts
}

// MARK: - GraphQL Response Wrapper

struct GQLDashboardEventsResponse: Codable {
    let dashboardEvents: DashboardEventsResult
}
