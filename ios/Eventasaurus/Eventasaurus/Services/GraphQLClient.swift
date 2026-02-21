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
                    id slug title tagline description
                    startsAt endsAt timezone
                    status visibility theme
                    coverImageUrl
                    isTicketed isVirtual virtualVenueUrl
                    isOrganizer participantCount myRsvpStatus
                    venue { id name address latitude longitude }
                    organizer { id name avatarUrl }
                    createdAt updatedAt
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
                    id slug title tagline description
                    startsAt endsAt timezone
                    status visibility theme
                    coverImageUrl
                    isTicketed isVirtual virtualVenueUrl
                    isOrganizer participantCount myRsvpStatus
                    venue { id name address latitude longitude }
                    organizer { id name avatarUrl }
                    createdAt updatedAt
                }
            }
            """,
            variables: ["slug": slug]
        )
        return result.myEvent
    }

    func fetchAttendingEvents(limit: Int? = nil) async throws -> [UserEvent] {
        var variables: [String: Any] = [:]
        if let limit { variables["limit"] = limit }

        let result: GQLAttendingEventsResponse = try await execute(
            query: """
            query AttendingEvents($limit: Int) {
                attendingEvents(limit: $limit) {
                    id slug title tagline
                    startsAt endsAt timezone
                    status visibility
                    coverImageUrl isOrganizer
                    participantCount myRsvpStatus
                    venue { id name address }
                    organizer { id name avatarUrl }
                }
            }
            """,
            variables: variables
        )
        return result.attendingEvents
    }

    // MARK: - Event Mutations

    func createEvent(input: CreateEventInput) async throws -> MutationResult<UserEvent> {
        let result: GQLCreateEventResponse = try await execute(
            query: """
            mutation CreateEvent($input: CreateEventInput!) {
                createEvent(input: $input) {
                    event {
                        id slug title tagline description
                        startsAt endsAt timezone
                        status visibility theme
                        coverImageUrl
                        isTicketed isVirtual virtualVenueUrl
                        isOrganizer participantCount
                        venue { id name address latitude longitude }
                        createdAt updatedAt
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
                        id slug title tagline description
                        startsAt endsAt timezone
                        status visibility theme
                        coverImageUrl
                        isTicketed isVirtual virtualVenueUrl
                        isOrganizer participantCount
                        venue { id name address latitude longitude }
                        createdAt updatedAt
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
                        id slug title status visibility
                        startsAt endsAt timezone
                        coverImageUrl participantCount
                        venue { id name address }
                        createdAt updatedAt
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
                        id slug title status
                        startsAt endsAt timezone
                        coverImageUrl participantCount
                        venue { id name address }
                        createdAt updatedAt
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
                        id slug title participantCount myRsvpStatus
                        startsAt endsAt venue { name }
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

    // MARK: - Image Upload

    func uploadImage(data: Data, filename: String, mimeType: String) async throws -> String {
        // Multipart form upload for Absinthe
        let boundary = UUID().uuidString
        var request = URLRequest(url: graphqlURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = try? await Clerk.shared.auth.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let query = """
        mutation UploadImage($file: Upload!) {
            uploadImage(file: $file) {
                url
                errors { field message }
            }
        }
        """

        var body = Data()
        // operations part
        let operations = """
        {"query": \(jsonString(query)), "variables": {"file": null}}
        """
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"operations\"\r\n\r\n")
        body.append(operations)
        body.append("\r\n")

        // map part
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"map\"\r\n\r\n")
        body.append("{\"0\": [\"variables.file\"]}")
        body.append("\r\n")

        // file part
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

    // MARK: - Core Execute

    private func execute<T: Decodable>(
        query: String,
        variables: [String: Any] = [:]
    ) async throws -> T {
        var request = URLRequest(url: graphqlURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = try? await Clerk.shared.auth.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

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
        let data = try! JSONSerialization.data(withJSONObject: string)
        return String(data: data, encoding: .utf8)!
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
