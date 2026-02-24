import Foundation
import ClerkKit

/// Lightweight GraphQL client for authenticated operations.
/// Uses the same URLSession + Clerk auth pattern as APIClient.
/// REST stays for public discovery; GraphQL handles all user-owned data.
@Observable
final class GraphQLClient {
    static let shared = GraphQLClient()

    private let graphqlURL: URL
    private let session = URLSession.shared

    /// Shared fragment with all UserEvent fields — single source of truth to prevent
    /// Codable decode crashes from partial query fragments.
    /// Note: organizer email is intentionally excluded here to avoid exposing it
    /// to attendees. Use `eventFieldsForOrganizer` in organizer-only queries.
    private static let eventFields = """
        id slug title tagline description
        startsAt endsAt timezone
        status visibility theme
        coverImageUrl
        isTicketed isVirtual virtualVenueUrl
        thresholdCount thresholdType
        isOrganizer participantCount myRsvpStatus
        venue { id name address latitude longitude }
        organizer { id name avatarUrl }
        organizers { id name avatarUrl }
        createdAt updatedAt
    """

    /// Extended fragment that includes organizer email — only for organizer-authorized queries.
    private static let eventFieldsForOrganizer = """
        id slug title tagline description
        startsAt endsAt timezone
        status visibility theme
        coverImageUrl
        isTicketed isVirtual virtualVenueUrl
        thresholdCount thresholdType
        isOrganizer participantCount myRsvpStatus
        venue { id name address latitude longitude }
        organizer { id name avatarUrl }
        organizers { id name email avatarUrl }
        createdAt updatedAt
    """

    init(baseURL: URL = AppConfig.apiBaseURL) {
        self.graphqlURL = baseURL.appendingPathComponent("api/graphql")
    }

    // MARK: - Profile

    func fetchMyProfile() async throws -> GQLUser {
        let result: GQLProfileResponse = try await execute(
            query: """
            query MyProfile {
                myProfile {
                    id name email username bio avatarUrl profileUrl
                    defaultCurrency timezone
                }
            }
            """
        )
        return result.myProfile
    }

    // MARK: - Event Queries

    func fetchMyEvents(limit: Int? = nil) async throws -> [UserEvent] {
        var variables: [String: Any] = [:]
        if let limit { variables["limit"] = limit }

        let result: GQLMyEventsResponse = try await execute(
            query: """
            query MyEvents($limit: Int) {
                myEvents(limit: $limit) {
                    \(Self.eventFieldsForOrganizer)
                }
            }
            """,
            variables: variables
        )
        return result.myEvents
    }

    func fetchMyEvent(slug: String) async throws -> UserEvent {
        let result: GQLMyEventResponse = try await execute(
            query: """
            query MyEvent($slug: String!) {
                myEvent(slug: $slug) {
                    \(Self.eventFieldsForOrganizer)
                }
            }
            """,
            variables: ["slug": slug]
        )
        return result.myEvent
    }

    /// Fetch event as a participant (no organizer requirement) — safe for all authenticated users.
    func fetchEventAsAttendee(slug: String) async throws -> UserEvent {
        let result: GQLEventAsParticipantResponse = try await execute(
            query: """
            query EventAsParticipant($slug: String!) {
                eventAsParticipant(slug: $slug) {
                    \(Self.eventFields)
                }
            }
            """,
            variables: ["slug": slug]
        )
        return result.eventAsParticipant
    }

    func fetchAttendingEvents(limit: Int? = nil) async throws -> [UserEvent] {
        var variables: [String: Any] = [:]
        if let limit { variables["limit"] = limit }

        let result: GQLAttendingEventsResponse = try await execute(
            query: """
            query AttendingEvents($limit: Int) {
                attendingEvents(limit: $limit) {
                    \(Self.eventFields)
                }
            }
            """,
            variables: variables
        )
        return result.attendingEvents
    }

    // MARK: - Dashboard

    func fetchDashboardEvents(
        timeFilter: DashboardTimeFilter = .upcoming,
        ownershipFilter: DashboardOwnershipFilter = .all,
        limit: Int = 50
    ) async throws -> DashboardEventsResult {
        let result: GQLDashboardEventsResponse = try await execute(
            query: """
            query DashboardEvents($timeFilter: DashboardTimeFilter, $ownershipFilter: DashboardOwnershipFilter, $limit: Int) {
                dashboardEvents(timeFilter: $timeFilter, ownershipFilter: $ownershipFilter, limit: $limit) {
                    events {
                        id slug title tagline description
                        startsAt endsAt timezone
                        status coverImageUrl isVirtual
                        userRole userStatus canManage
                        participantCount
                        venue { id name address latitude longitude }
                        createdAt updatedAt
                    }
                    filterCounts {
                        upcoming past archived created participating
                    }
                }
            }
            """,
            variables: [
                "timeFilter": timeFilter.rawValue,
                "ownershipFilter": ownershipFilter.rawValue,
                "limit": limit
            ]
        )
        return result.dashboardEvents
    }

    // MARK: - Event Mutations

    func createEvent(input: CreateEventInput) async throws -> MutationResult<UserEvent> {
        let result: GQLCreateEventResponse = try await execute(
            query: """
            mutation CreateEvent($input: CreateEventInput!) {
                createEvent(input: $input) {
                    event {
                        \(Self.eventFieldsForOrganizer)
                    }
                    errors { field message }
                }
            }
            """,
            variables: ["input": input.toVariables()]
        )
        let mutation = result.createEvent
        if let errors = mutation.errors, !errors.isEmpty {
            throw GraphQLMutationError.validationErrors(errors)
        }
        guard let event = mutation.event else {
            throw GraphQLMutationError.noData
        }
        return MutationResult(data: event, errors: mutation.errors ?? [])
    }

    func updateEvent(slug: String, input: UpdateEventInput) async throws -> MutationResult<UserEvent> {
        let result: GQLUpdateEventResponse = try await execute(
            query: """
            mutation UpdateEvent($slug: String!, $input: UpdateEventInput!) {
                updateEvent(slug: $slug, input: $input) {
                    event {
                        \(Self.eventFieldsForOrganizer)
                    }
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug, "input": input.toVariables()]
        )
        let mutation = result.updateEvent
        if let errors = mutation.errors, !errors.isEmpty {
            throw GraphQLMutationError.validationErrors(errors)
        }
        guard let event = mutation.event else {
            throw GraphQLMutationError.noData
        }
        return MutationResult(data: event, errors: mutation.errors ?? [])
    }

    func deleteEvent(slug: String) async throws {
        let result: GQLDeleteEventResponse = try await execute(
            query: """
            mutation DeleteEvent($slug: String!) {
                deleteEvent(slug: $slug) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug]
        )
        let mutation = result.deleteEvent
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    func publishEvent(slug: String) async throws -> UserEvent {
        let result: GQLPublishEventResponse = try await execute(
            query: """
            mutation PublishEvent($slug: String!) {
                publishEvent(slug: $slug) {
                    event {
                        \(Self.eventFieldsForOrganizer)
                    }
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug]
        )
        let mutation = result.publishEvent
        if let errors = mutation.errors, !errors.isEmpty {
            throw GraphQLMutationError.validationErrors(errors)
        }
        guard let event = mutation.event else {
            throw GraphQLMutationError.noData
        }
        return event
    }

    func cancelEvent(slug: String) async throws -> UserEvent {
        let result: GQLCancelEventResponse = try await execute(
            query: """
            mutation CancelEvent($slug: String!) {
                cancelEvent(slug: $slug) {
                    event {
                        \(Self.eventFieldsForOrganizer)
                    }
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug]
        )
        let mutation = result.cancelEvent
        if let errors = mutation.errors, !errors.isEmpty {
            throw GraphQLMutationError.validationErrors(errors)
        }
        guard let event = mutation.event else {
            throw GraphQLMutationError.noData
        }
        return event
    }

    // MARK: - RSVP

    func rsvp(slug: String, status: RsvpStatus) async throws -> UserEvent {
        let result: GQLRsvpResponse = try await execute(
            query: """
            mutation Rsvp($slug: String!, $status: RsvpStatus!) {
                rsvp(slug: $slug, status: $status) {
                    event {
                        \(Self.eventFields)
                    }
                    status
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug, "status": status.rawValue]
        )
        let mutation = result.rsvp
        if let errors = mutation.errors, !errors.isEmpty {
            throw GraphQLMutationError.validationErrors(errors)
        }
        guard let event = mutation.event else {
            throw GraphQLMutationError.noData
        }
        return event
    }

    // MARK: - Cancel RSVP

    func cancelRsvp(slug: String) async throws {
        let result: GQLCancelRsvpResponse = try await execute(
            query: """
            mutation CancelRsvp($slug: String!) {
                cancelRsvp(slug: $slug) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug]
        )
        let mutation = result.cancelRsvp
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    // MARK: - Plan

    func createPlan(slug: String, emails: [String], friendIds: [String] = [], message: String? = nil) async throws -> GQLPlan {
        var variables: [String: Any] = ["slug": slug, "emails": emails]
        if !friendIds.isEmpty { variables["friendIds"] = friendIds }
        if let message { variables["message"] = message }

        let result: GQLPlanResponse = try await execute(
            query: """
            mutation CreatePlan($slug: String!, $emails: [String!]!, $friendIds: [ID!], $message: String) {
                createPlan(slug: $slug, emails: $emails, friendIds: $friendIds, message: $message) {
                    plan {
                        slug title inviteCount createdAt alreadyExists
                    }
                    errors { field message }
                }
            }
            """,
            variables: variables
        )
        let mutation = result.createPlan
        if let errors = mutation.errors, !errors.isEmpty {
            throw GraphQLMutationError.validationErrors(errors)
        }
        guard let plan = mutation.plan else {
            throw GraphQLMutationError.noData
        }
        return plan
    }

    func fetchMyPlan(slug: String) async throws -> GQLPlan? {
        let result: GQLMyPlanResponse = try await execute(
            query: """
            query MyPlan($slug: String!) {
                myPlan(slug: $slug) {
                    slug title inviteCount createdAt alreadyExists
                }
            }
            """,
            variables: ["slug": slug]
        )
        return result.myPlan
    }

    // MARK: - Participant Suggestions

    func fetchParticipantSuggestions(limit: Int = 20) async throws -> [ParticipantSuggestion] {
        let result: GQLParticipantSuggestionsResponse = try await execute(
            query: """
            query ParticipantSuggestions($limit: Int) {
                participantSuggestions(limit: $limit) {
                    userId name maskedEmail username
                    participationCount totalScore recommendationLevel
                    avatarUrl
                }
            }
            """,
            variables: ["limit": limit]
        )
        return result.participantSuggestions
    }

    // MARK: - Participant Management

    func fetchEventParticipants(slug: String, status: String? = nil, limit: Int? = nil, offset: Int? = nil) async throws -> [EventParticipant] {
        var variables: [String: Any] = ["slug": slug]
        if let status { variables["status"] = status }
        if let limit { variables["limit"] = limit }
        if let offset { variables["offset"] = offset }

        let result: GQLEventParticipantsResponse = try await execute(
            query: """
            query EventParticipants($slug: String!, $status: String, $limit: Int, $offset: Int) {
                eventParticipants(slug: $slug, status: $status, limit: $limit, offset: $offset) {
                    id role status rawStatus
                    invitedAt createdAt
                    emailStatus invitationMessage email
                    user { id name email }
                }
            }
            """,
            variables: variables
        )
        return result.eventParticipants
    }

    func inviteGuests(slug: String, emails: [String], friendIds: [String] = [], message: String? = nil) async throws -> Int {
        var variables: [String: Any] = ["slug": slug, "emails": emails]
        if !friendIds.isEmpty { variables["friendIds"] = friendIds }
        if let message { variables["message"] = message }

        let result: GQLInviteGuestsResponse = try await execute(
            query: """
            mutation InviteGuests($slug: String!, $emails: [String!]!, $friendIds: [ID!], $message: String) {
                inviteGuests(slug: $slug, emails: $emails, friendIds: $friendIds, message: $message) {
                    inviteCount
                    errors { field message }
                }
            }
            """,
            variables: variables
        )
        let mutation = result.inviteGuests
        if let errors = mutation.errors, !errors.isEmpty {
            throw GraphQLMutationError.validationErrors(errors)
        }
        return mutation.inviteCount
    }

    func removeParticipant(slug: String, userId: String) async throws {
        let result: GQLRemoveParticipantResponse = try await execute(
            query: """
            mutation RemoveParticipant($slug: String!, $userId: ID!) {
                removeParticipant(slug: $slug, userId: $userId) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug, "userId": userId]
        )
        let mutation = result.removeParticipant
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    func resendInvitation(slug: String, userId: String) async throws {
        let result: GQLResendInvitationResponse = try await execute(
            query: """
            mutation ResendInvitation($slug: String!, $userId: ID!) {
                resendInvitation(slug: $slug, userId: $userId) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug, "userId": userId]
        )
        let mutation = result.resendInvitation
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    func updateParticipantStatus(slug: String, userId: String, status: RsvpStatus) async throws {
        let result: GQLUpdateParticipantStatusResponse = try await execute(
            query: """
            mutation UpdateParticipantStatus($slug: String!, $userId: ID!, $status: RsvpStatus!) {
                updateParticipantStatus(slug: $slug, userId: $userId, status: $status) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug, "userId": userId, "status": status.rawValue]
        )
        let mutation = result.updateParticipantStatus
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    // MARK: - Poll Queries

    func fetchEventPolls(slug: String) async throws -> [EventPoll] {
        let result: GQLEventPollsResponse = try await execute(
            query: """
            query EventPolls($slug: String!) {
                eventPolls(slug: $slug) {
                    id title description
                    pollType votingSystem phase votingDeadline
                    options { id title description voteCount averageScore }
                    myVotes { id optionId score voteValue voteRank }
                }
            }
            """,
            variables: ["slug": slug]
        )
        return result.eventPolls
    }

    func voteOnPoll(pollId: String, optionId: String, score: Int? = nil, voteValue: String? = nil) async throws {
        var variables: [String: Any] = ["pollId": pollId, "optionId": optionId]
        if let score { variables["score"] = score }
        if let voteValue { variables["voteValue"] = voteValue }

        let result: GQLVoteOnPollResponse = try await execute(
            query: """
            mutation VoteOnPoll($pollId: ID!, $optionId: ID!, $score: Int, $voteValue: String) {
                voteOnPoll(pollId: $pollId, optionId: $optionId, score: $score, voteValue: $voteValue) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: variables
        )
        let mutation = result.voteOnPoll
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    // Phase 2: Clear votes for re-voting
    func clearMyPollVotes(pollId: String) async throws {
        let _: GQLClearPollVotesResponse = try await execute(
            query: """
            mutation ClearMyPollVotes($pollId: ID!) {
                clearMyPollVotes(pollId: $pollId) { id }
            }
            """,
            variables: ["pollId": pollId]
        )
    }

    // Phase 3: Suggest a new option
    func createPollOption(pollId: String, title: String, description: String? = nil) async throws {
        var variables: [String: Any] = ["pollId": pollId, "title": title]
        if let description { variables["description"] = description }

        let _: GQLCreatePollOptionResponse = try await execute(
            query: """
            mutation CreatePollOption($pollId: ID!, $title: String!, $description: String) {
                createPollOption(pollId: $pollId, title: $title, description: $description) { id }
            }
            """,
            variables: variables
        )
    }

    // Phase 4: Create poll
    func createPoll(eventId: String, title: String, votingSystem: String, description: String? = nil, votingDeadline: Date? = nil) async throws {
        var variables: [String: Any] = ["eventId": eventId, "title": title, "votingSystem": votingSystem]
        if let description { variables["description"] = description }
        if let votingDeadline {
            let formatter = ISO8601DateFormatter()
            variables["votingDeadline"] = formatter.string(from: votingDeadline)
        }

        let _: GQLCreatePollResponse = try await execute(
            query: """
            mutation CreatePoll($eventId: ID!, $title: String!, $votingSystem: String!, $description: String, $votingDeadline: DateTime) {
                createPoll(eventId: $eventId, title: $title, votingSystem: $votingSystem, description: $description, votingDeadline: $votingDeadline) { id }
            }
            """,
            variables: variables
        )
    }

    // Phase 4: Update poll
    func updatePoll(pollId: String, title: String? = nil, description: String? = nil, votingDeadline: Date? = nil) async throws {
        var variables: [String: Any] = ["pollId": pollId]
        if let title { variables["title"] = title }
        if let description { variables["description"] = description }
        if let votingDeadline {
            let formatter = ISO8601DateFormatter()
            variables["votingDeadline"] = formatter.string(from: votingDeadline)
        }

        let _: GQLUpdatePollResponse = try await execute(
            query: """
            mutation UpdatePoll($pollId: ID!, $title: String, $description: String, $votingDeadline: DateTime) {
                updatePoll(pollId: $pollId, title: $title, description: $description, votingDeadline: $votingDeadline) { id }
            }
            """,
            variables: variables
        )
    }

    // Phase 4: Delete poll
    func deletePoll(pollId: String) async throws {
        let result: GQLDeletePollResponse = try await execute(
            query: """
            mutation DeletePoll($pollId: ID!) {
                deletePoll(pollId: $pollId) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["pollId": pollId]
        )
        let mutation = result.deletePoll
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    // Phase 4: Transition poll phase
    func transitionPollPhase(pollId: String, phase: String) async throws {
        let _: GQLTransitionPollPhaseResponse = try await execute(
            query: """
            mutation TransitionPollPhase($pollId: ID!, $phase: String!) {
                transitionPollPhase(pollId: $pollId, phase: $phase) { id phase }
            }
            """,
            variables: ["pollId": pollId, "phase": phase]
        )
    }

    // Phase 4: Delete poll option
    func deletePollOption(optionId: String) async throws {
        let result: GQLDeletePollOptionResponse = try await execute(
            query: """
            mutation DeletePollOption($optionId: ID!) {
                deletePollOption(optionId: $optionId) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["optionId": optionId]
        )
        let mutation = result.deletePollOption
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    // Phase 5: Fetch poll voting stats
    func fetchPollStats(pollId: String) async throws -> PollVotingStats {
        let result: GQLPollVotingStatsResponse = try await execute(
            query: """
            query PollVotingStats($pollId: ID!) {
                pollVotingStats(pollId: $pollId) {
                    pollId pollTitle votingSystem phase totalUniqueVoters
                    options {
                        optionId optionTitle optionDescription
                        tally {
                            total yes maybe no selected percentage
                            averageScore scoreDistribution
                            averageRank firstPlaceCount
                        }
                    }
                }
            }
            """,
            variables: ["pollId": pollId]
        )
        return result.pollVotingStats
    }

    // MARK: - Organizer Management

    func addOrganizer(slug: String, email: String) async throws {
        let result: GQLAddOrganizerResponse = try await execute(
            query: """
            mutation AddOrganizer($slug: String!, $email: String!) {
                addOrganizer(slug: $slug, email: $email) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug, "email": email]
        )
        let mutation = result.addOrganizer
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    func removeOrganizer(slug: String, userId: String) async throws {
        let result: GQLRemoveOrganizerResponse = try await execute(
            query: """
            mutation RemoveOrganizer($slug: String!, $userId: ID!) {
                removeOrganizer(slug: $slug, userId: $userId) {
                    success
                    errors { field message }
                }
            }
            """,
            variables: ["slug": slug, "userId": userId]
        )
        let mutation = result.removeOrganizer
        if !mutation.success {
            let errors = mutation.errors ?? []
            throw GraphQLMutationError.validationErrors(errors)
        }
    }

    // MARK: - User Search

    func searchUsersForOrganizers(query: String, slug: String, limit: Int = 20) async throws -> [UserSearchResult] {
        let result: GQLSearchUsersForOrganizersResponse = try await execute(
            query: """
            query SearchUsersForOrganizers($query: String!, $slug: String!, $limit: Int) {
                searchUsersForOrganizers(query: $query, slug: $slug, limit: $limit) {
                    id name username email avatarUrl
                }
            }
            """,
            variables: ["query": query, "slug": slug, "limit": limit]
        )
        return result.searchUsersForOrganizers
    }

    // MARK: - Venue Queries

    func searchVenues(query: String, limit: Int = 20) async throws -> [UserEventVenue] {
        let result: GQLSearchVenuesResponse = try await execute(
            query: """
            query SearchVenues($query: String!, $limit: Int) {
                searchVenues(query: $query, limit: $limit) {
                    id name address latitude longitude
                }
            }
            """,
            variables: ["query": query, "limit": limit]
        )
        return result.searchVenues
    }

    func fetchRecentVenues(limit: Int = 10) async throws -> [RecentVenue] {
        let result: GQLRecentVenuesResponse = try await execute(
            query: """
            query MyRecentVenues($limit: Int) {
                myRecentVenues(limit: $limit) {
                    id name address latitude longitude usageCount
                }
            }
            """,
            variables: ["limit": limit]
        )
        return result.myRecentVenues
    }

    func createVenue(
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        cityName: String? = nil,
        countryCode: String? = nil
    ) async throws -> UserEventVenue {
        var variables: [String: Any] = ["name": name]
        if let address { variables["address"] = address }
        if let latitude { variables["latitude"] = latitude }
        if let longitude { variables["longitude"] = longitude }
        if let cityName { variables["cityName"] = cityName }
        if let countryCode { variables["countryCode"] = countryCode }

        let result: GQLCreateVenueResponse = try await execute(
            query: """
            mutation CreateVenue($name: String!, $address: String, $latitude: Float, $longitude: Float, $cityName: String, $countryCode: String) {
                createVenue(name: $name, address: $address, latitude: $latitude, longitude: $longitude, cityName: $cityName, countryCode: $countryCode) {
                    venue { id name address latitude longitude }
                    errors { field message }
                }
            }
            """,
            variables: variables
        )
        let mutation = result.createVenue
        if let errors = mutation.errors, !errors.isEmpty {
            throw GraphQLMutationError.validationErrors(errors)
        }
        guard let venue = mutation.venue else {
            throw GraphQLMutationError.noData
        }
        return venue
    }

    // MARK: - Image Upload

    func uploadImage(data: Data, filename: String, mimeType: String) async throws -> String {
        // Multipart form upload for Absinthe
        let boundary = UUID().uuidString
        var request = URLRequest(url: graphqlURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        await applyAuthHeaders(to: &request)

        let query = """
        mutation UploadImage($file: Upload!) {
            uploadImage(file: $file) {
                url
                errors { field message }
            }
        }
        """

        var body = Data()
        // query part (Absinthe native multipart format)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"query\"\r\n\r\n")
        body.append(query)
        body.append("\r\n")

        // variables part — "file" value references the form field name containing the upload
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"variables\"\r\n\r\n")
        body.append("{\"file\": \"0\"}")
        body.append("\r\n")

        // file part — field name "0" matches the variable reference above
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"0\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw GraphQLError.serverError
        }

        let decoded = try JSONDecoder().decode(
            GraphQLResponse<GQLUploadResponse>.self, from: responseData
        )
        if let errors = decoded.errors, !errors.isEmpty {
            throw GraphQLError.queryErrors(errors.map(\.message))
        }
        guard let url = decoded.data?.uploadImage.url else {
            throw GraphQLMutationError.noData
        }
        return url
    }

    // MARK: - Dev Auth (DEBUG only)

    #if DEBUG
    func fetchDevQuickLoginUsers() async throws -> DevQuickLoginUsers {
        let result: GQLDevQuickLoginUsersResponse = try await execute(
            query: """
            query DevQuickLoginUsers {
                devQuickLoginUsers {
                    personal { id name email label }
                    organizers { id name email label }
                    participants { id name email label }
                }
            }
            """
        )
        return result.devQuickLoginUsers
    }
    #endif

    // MARK: - Auth Headers

    private func applyAuthHeaders(to request: inout URLRequest) async {
        #if DEBUG
        let devAuth = await MainActor.run { (DevAuthService.shared.isDevAuthActive, DevAuthService.shared.selectedUserId) }
        if devAuth.0, let userId = devAuth.1 {
            request.setValue(userId, forHTTPHeaderField: "X-Dev-User-Id")
            return
        }
        #endif
        if let token = try? await Clerk.shared.auth.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Core Execute

    private func execute<T: Decodable>(
        query: String,
        variables: [String: Any] = [:]
    ) async throws -> T {
        var request = URLRequest(url: graphqlURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        await applyAuthHeaders(to: &request)

        var body: [String: Any] = ["query": query]
        if !variables.isEmpty {
            body["variables"] = variables
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GraphQLError.serverError
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let responseBody = String(data: data, encoding: .utf8)
            throw GraphQLError.httpError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let graphqlResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)

        if let errors = graphqlResponse.errors, !errors.isEmpty {
            let messages = errors.map(\.message)
            if messages.contains(where: { $0.contains("UNAUTHENTICATED") }) {
                throw GraphQLError.unauthenticated
            }
            throw GraphQLError.queryErrors(messages)
        }

        guard let resultData = graphqlResponse.data else {
            throw GraphQLError.noData
        }

        return resultData
    }

    private func jsonString(_ string: String) -> String {
        // Wrap in array to guarantee valid top-level JSON, then extract the encoded string
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let arrayString = String(data: data, encoding: .utf8),
              arrayString.count > 2 else {
            // Fallback should never be reached, but handle gracefully
            let escaped = string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "\"\(escaped)\""
        }
        // Strip the surrounding [ and ]
        let start = arrayString.index(after: arrayString.startIndex)
        let end = arrayString.index(before: arrayString.endIndex)
        return String(arrayString[start..<end])
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

// MARK: - GraphQL Response Types

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLResponseError]?
}

struct GraphQLResponseError: Decodable {
    let message: String
    let path: [String]?
}

// MARK: - Errors

enum GraphQLError: Error, LocalizedError {
    case serverError
    case httpError(statusCode: Int, body: String?)
    case unauthenticated
    case queryErrors([String])
    case noData

    var errorDescription: String? {
        switch self {
        case .serverError: return "Server error"
        case .httpError(let code, _): return "Server error (HTTP \(code))"
        case .unauthenticated: return "Please sign in to continue"
        case .queryErrors(let messages): return messages.joined(separator: ", ")
        case .noData: return "No data returned"
        }
    }
}

enum GraphQLMutationError: Error, LocalizedError {
    case validationErrors([InputError])
    case noData

    var errorDescription: String? {
        switch self {
        case .validationErrors(let errors):
            return errors.map { "\($0.field): \($0.message)" }.joined(separator: "\n")
        case .noData:
            return "Operation completed but no data returned"
        }
    }

    var fieldErrors: [String: String] {
        switch self {
        case .validationErrors(let errors):
            return Dictionary(errors.map { ($0.field, $0.message) }, uniquingKeysWith: { first, _ in first })
        case .noData:
            return [:]
        }
    }
}

// MARK: - Generic Result

struct MutationResult<T> {
    let data: T
    let errors: [InputError]
}
