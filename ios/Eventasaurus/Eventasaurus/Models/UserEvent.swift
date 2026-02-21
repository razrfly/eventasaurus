import Foundation

// MARK: - User Event Model (GraphQL)
//
// Separate from the discovery `Event` model which handles polymorphic types
// (movie_group, container_group, etc.). UserEvent is specifically for
// user-created/managed events returned by the GraphQL API.

struct UserEvent: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let tagline: String?
    let description: String?
    let startsAt: Date?
    let endsAt: Date?
    let timezone: String?
    let status: EventStatus
    let visibility: EventVisibility
    let theme: EventTheme?
    let coverImageUrl: String?
    let isTicketed: Bool
    let isVirtual: Bool
    let virtualVenueUrl: String?
    let isOrganizer: Bool
    let participantCount: Int
    let myRsvpStatus: RsvpStatus?
    let venue: UserEventVenue?
    let organizer: UserEventOrganizer?
    let createdAt: Date?
    let updatedAt: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(slug)
    }

    static func == (lhs: UserEvent, rhs: UserEvent) -> Bool {
        lhs.slug == rhs.slug
    }
}

struct UserEventVenue: Codable, Hashable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

struct UserEventOrganizer: Codable, Hashable {
    let id: String
    let name: String
    let avatarUrl: String?
}

// MARK: - Enums

enum EventStatus: String, Codable, CaseIterable {
    case draft = "DRAFT"
    case polling = "POLLING"
    case threshold = "THRESHOLD"
    case confirmed = "CONFIRMED"
    case canceled = "CANCELED"

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .polling: return "Polling"
        case .threshold: return "Threshold"
        case .confirmed: return "Confirmed"
        case .canceled: return "Canceled"
        }
    }

    var icon: String {
        switch self {
        case .draft: return "pencil.circle"
        case .polling: return "chart.bar"
        case .threshold: return "person.3"
        case .confirmed: return "checkmark.circle.fill"
        case .canceled: return "xmark.circle"
        }
    }
}

enum EventVisibility: String, Codable, CaseIterable {
    case `public` = "PUBLIC"
    case `private` = "PRIVATE"

    var displayName: String {
        switch self {
        case .public: return "Public"
        case .private: return "Private"
        }
    }

    var icon: String {
        switch self {
        case .public: return "globe"
        case .private: return "lock"
        }
    }
}

enum EventTheme: String, Codable, CaseIterable {
    case minimal = "MINIMAL"
    case cosmic = "COSMIC"
    case velocity = "VELOCITY"
    case retro = "RETRO"
    case celebration = "CELEBRATION"
    case nature = "NATURE"
    case professional = "PROFESSIONAL"

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .cosmic: return "Cosmic"
        case .velocity: return "Velocity"
        case .retro: return "Retro"
        case .celebration: return "Celebration"
        case .nature: return "Nature"
        case .professional: return "Professional"
        }
    }
}

enum RsvpStatus: String, Codable, CaseIterable {
    case going = "GOING"
    case interested = "INTERESTED"
    case notGoing = "NOT_GOING"

    var displayName: String {
        switch self {
        case .going: return "Going"
        case .interested: return "Interested"
        case .notGoing: return "Not Going"
        }
    }

    var icon: String {
        switch self {
        case .going: return "checkmark.circle.fill"
        case .interested: return "star.circle.fill"
        case .notGoing: return "xmark.circle"
        }
    }

    /// Initialize from REST API attendance status strings.
    init?(restStatus: String) {
        switch restStatus {
        case "accepted": self = .going
        case "interested": self = .interested
        default: return nil
        }
    }
}

// MARK: - GraphQL Input Types

struct CreateEventInput {
    var title: String
    var description: String?
    var tagline: String?
    var startsAt: Date?
    var endsAt: Date?
    var timezone: String?
    var visibility: EventVisibility?
    var theme: EventTheme?
    var coverImageUrl: String?
    var isTicketed: Bool?
    var isVirtual: Bool?
    var virtualVenueUrl: String?

    func toVariables() -> [String: Any] {
        var vars: [String: Any] = ["title": title]
        if let description { vars["description"] = description }
        if let tagline { vars["tagline"] = tagline }
        if let startsAt { vars["startsAt"] = ISO8601DateFormatter().string(from: startsAt) }
        if let endsAt { vars["endsAt"] = ISO8601DateFormatter().string(from: endsAt) }
        if let timezone { vars["timezone"] = timezone }
        if let visibility { vars["visibility"] = visibility.rawValue }
        if let theme { vars["theme"] = theme.rawValue }
        if let coverImageUrl { vars["coverImageUrl"] = coverImageUrl }
        if let isTicketed { vars["isTicketed"] = isTicketed }
        if let isVirtual { vars["isVirtual"] = isVirtual }
        if let virtualVenueUrl { vars["virtualVenueUrl"] = virtualVenueUrl }
        return vars
    }
}

struct UpdateEventInput {
    var title: String?
    var description: String?
    var tagline: String?
    var startsAt: Date?
    var endsAt: Date?
    var timezone: String?
    var visibility: EventVisibility?
    var theme: EventTheme?
    var coverImageUrl: String?
    var isTicketed: Bool?
    var isVirtual: Bool?
    var virtualVenueUrl: String?

    func toVariables() -> [String: Any] {
        var vars: [String: Any] = [:]
        if let title { vars["title"] = title }
        if let description { vars["description"] = description }
        if let tagline { vars["tagline"] = tagline }
        if let startsAt { vars["startsAt"] = ISO8601DateFormatter().string(from: startsAt) }
        if let endsAt { vars["endsAt"] = ISO8601DateFormatter().string(from: endsAt) }
        if let timezone { vars["timezone"] = timezone }
        if let visibility { vars["visibility"] = visibility.rawValue }
        if let theme { vars["theme"] = theme.rawValue }
        if let coverImageUrl { vars["coverImageUrl"] = coverImageUrl }
        if let isTicketed { vars["isTicketed"] = isTicketed }
        if let isVirtual { vars["isVirtual"] = isVirtual }
        if let virtualVenueUrl { vars["virtualVenueUrl"] = virtualVenueUrl }
        return vars
    }
}

// MARK: - GraphQL Shared Types

struct InputError: Codable {
    let field: String
    let message: String
}

// MARK: - GraphQL Response Wrappers

struct GQLUser: Codable {
    let id: String
    let name: String
    let email: String?
    let username: String?
    let bio: String?
    let avatarUrl: String
    let profileUrl: String?
    let defaultCurrency: String?
    let timezone: String?
}

struct GQLProfileResponse: Codable {
    let myProfile: GQLUser
}

struct GQLMyEventsResponse: Codable {
    let myEvents: [UserEvent]
}

struct GQLMyEventResponse: Codable {
    let myEvent: UserEvent
}

struct GQLAttendingEventsResponse: Codable {
    let attendingEvents: [UserEvent]
}

struct GQLCreateEventResponse: Codable {
    let createEvent: GQLEventMutationResult
}

struct GQLUpdateEventResponse: Codable {
    let updateEvent: GQLEventMutationResult
}

struct GQLPublishEventResponse: Codable {
    let publishEvent: GQLEventMutationResult
}

struct GQLCancelEventResponse: Codable {
    let cancelEvent: GQLEventMutationResult
}

struct GQLDeleteEventResponse: Codable {
    let deleteEvent: GQLDeleteResult
}

struct GQLEventMutationResult: Codable {
    let event: UserEvent?
    let errors: [InputError]?
}

struct GQLDeleteResult: Codable {
    let success: Bool
    let errors: [InputError]?
}

struct GQLRsvpResponse: Codable {
    let rsvp: GQLRsvpResult
}

struct GQLRsvpResult: Codable {
    let event: UserEvent?
    let status: RsvpStatus?
    let errors: [InputError]?
}

struct GQLCancelRsvpResponse: Codable {
    let cancelRsvp: GQLCancelRsvpResult
}

struct GQLCancelRsvpResult: Codable {
    let success: Bool
    let errors: [InputError]?
}

struct GQLPlanResponse: Codable {
    let createPlan: GQLPlanResult
}

struct GQLPlanResult: Codable {
    let plan: GQLPlan?
    let errors: [InputError]?
}

struct GQLMyPlanResponse: Codable {
    let myPlan: GQLPlan?
}

struct GQLPlan: Codable, Identifiable {
    var id: String { slug }
    let slug: String
    let title: String
    let inviteCount: Int
    let createdAt: String?
    let alreadyExists: Bool?
}

struct GQLUploadResponse: Codable {
    let uploadImage: GQLUploadResult
}

struct GQLUploadResult: Codable {
    let url: String?
    let errors: [InputError]?
}

// MARK: - Participant Suggestions

struct ParticipantSuggestion: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let name: String?
    let email: String
    let username: String?
    let participationCount: Int
    let totalScore: Double
    let recommendationLevel: String
    let avatarUrl: String
}

struct GQLParticipantSuggestionsResponse: Codable {
    let participantSuggestions: [ParticipantSuggestion]
}

// MARK: - Message Templates

enum MessageTemplate: String, CaseIterable, Identifiable {
    case casual, formal, excited, group
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .casual: return "Casual"
        case .formal: return "Formal"
        case .excited: return "Excited"
        case .group: return "Group"
        }
    }

    var icon: String {
        switch self {
        case .casual: return "hand.wave"
        case .formal: return "envelope.open"
        case .excited: return "party.popper"
        case .group: return "person.3"
        }
    }

    var text: String {
        switch self {
        case .casual:
            return "Hi! I'd love for you to join me at this event. It's going to be fun!"
        case .formal:
            return "You're cordially invited to join us for this special event. We would be delighted to have you attend."
        case .excited:
            return "Hey! I found this amazing event and immediately thought of you. Let's go together!"
        case .group:
            return "Hey everyone! Let's all go to this event together. It'll be a great time to catch up!"
        }
    }
}
