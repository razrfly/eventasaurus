import Foundation
import SwiftUI

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
    let organizers: [UserEventOrganizer]?
    let thresholdCount: Int?
    let thresholdType: String?
    let createdAt: Date?
    let updatedAt: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(slug)
    }

    static func == (lhs: UserEvent, rhs: UserEvent) -> Bool {
        lhs.slug == rhs.slug
    }
}

struct UserEventVenue: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

struct RecentVenue: Codable, Identifiable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let usageCount: Int
}

struct UserEventOrganizer: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let email: String?
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

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = RsvpStatus(rawValue: raw) ?? .interested
    }

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

// MARK: - User Search Result (Organizer Search)

struct UserSearchResult: Codable, Identifiable {
    let id: String
    let name: String
    let username: String?
    let email: String?
    let avatarUrl: String?
}

struct GQLSearchUsersForOrganizersResponse: Codable {
    let searchUsersForOrganizers: [UserSearchResult]
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
    var venueId: String?

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
        if let venueId { vars["venueId"] = venueId }
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
    var venueId: String?
    var clearVenue: Bool = false

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
        if clearVenue {
            vars["venueId"] = NSNull()
        } else if let venueId {
            vars["venueId"] = venueId
        }
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

// MARK: - Venue Response Wrappers

struct GQLSearchVenuesResponse: Codable {
    let searchVenues: [UserEventVenue]
}

struct GQLRecentVenuesResponse: Codable {
    let myRecentVenues: [RecentVenue]
}

struct GQLCreateVenueResponse: Codable {
    let createVenue: GQLCreateVenueResult
}

struct GQLCreateVenueResult: Codable {
    let venue: UserEventVenue?
    let errors: [InputError]?
}

// MARK: - Organizer Response Wrappers

struct GQLAddOrganizerResponse: Codable {
    let addOrganizer: GQLSuccessResult
}

struct GQLRemoveOrganizerResponse: Codable {
    let removeOrganizer: GQLSuccessResult
}

// MARK: - Poll Models

struct EventPoll: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let pollType: String
    let votingSystem: String
    let phase: String
    let votingDeadline: Date?
    let options: [PollOption]
    let myVotes: [PollVote]?

    var isClosed: Bool {
        phase == "closed"
    }

    var isVotingActive: Bool {
        !isClosed && (votingDeadline == nil || (votingDeadline ?? .distantPast) > Date())
    }
}

struct PollOption: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let voteCount: Int
    let averageScore: Double?
}

struct PollVote: Codable, Identifiable {
    let id: String
    let optionId: String
    let score: Int?
}

// MARK: - Poll Response Wrappers

struct GQLEventPollsResponse: Codable {
    let eventPolls: [EventPoll]
}

struct GQLVoteOnPollResponse: Codable {
    let voteOnPoll: GQLSuccessResult
}

// MARK: - Event Participant (Organizer View)

struct EventParticipant: Codable, Identifiable {
    let id: String
    let role: String?
    let status: RsvpStatus
    let rawStatus: String
    let invitedAt: Date?
    let createdAt: Date
    let emailStatus: String?
    let invitationMessage: String?
    let email: String?
    let user: ParticipantUser?
}

struct ParticipantUser: Codable, Hashable {
    let id: String
    let name: String
    let email: String?
}

enum EmailDeliveryStatus: String, CaseIterable {
    case notSent = "not_sent"
    case sent = "sent"
    case delivered = "delivered"
    case failed = "failed"
    case bounced = "bounced"

    init(from string: String?) {
        self = EmailDeliveryStatus(rawValue: string ?? "not_sent") ?? .notSent
    }

    var displayName: String {
        switch self {
        case .notSent: return "Not Sent"
        case .sent: return "Sent"
        case .delivered: return "Delivered"
        case .failed: return "Failed"
        case .bounced: return "Bounced"
        }
    }

    var icon: String {
        switch self {
        case .notSent: return "envelope"
        case .sent: return "paperplane.fill"
        case .delivered: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .bounced: return "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notSent: return .secondary
        case .sent: return .blue
        case .delivered: return .green
        case .failed: return .red
        case .bounced: return .orange
        }
    }
}

// MARK: - Participant Suggestions

enum RecommendationLevel: String, Codable {
    case highlyRecommended = "HIGHLY_RECOMMENDED"
    case recommended = "RECOMMENDED"
    case suggested = "SUGGESTED"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = RecommendationLevel(rawValue: raw) ?? .unknown
    }
}

struct ParticipantSuggestion: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let name: String?
    let maskedEmail: String?
    let username: String?
    let participationCount: Int
    let totalScore: Double
    let recommendationLevel: RecommendationLevel
    let avatarUrl: String?
}

struct GQLParticipantSuggestionsResponse: Codable {
    let participantSuggestions: [ParticipantSuggestion]
}

// MARK: - GraphQL Response Wrappers (Participants)

struct GQLEventParticipantsResponse: Codable {
    let eventParticipants: [EventParticipant]
}

struct GQLInviteGuestsResponse: Codable {
    let inviteGuests: GQLInviteGuestsResult
}

struct GQLInviteGuestsResult: Codable {
    let inviteCount: Int
    let errors: [InputError]?
}

struct GQLRemoveParticipantResponse: Codable {
    let removeParticipant: GQLSuccessResult
}

struct GQLResendInvitationResponse: Codable {
    let resendInvitation: GQLSuccessResult
}

struct GQLUpdateParticipantStatusResponse: Codable {
    let updateParticipantStatus: GQLSuccessResult
}

struct GQLSuccessResult: Codable {
    let success: Bool
    let errors: [InputError]?
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
