import Foundation
import ClerkKit

@Observable
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session = URLSession.shared
    private let decoder: JSONDecoder

    init(baseURL: URL = URL(string: "http://localhost:4000")!) {
        self.baseURL = baseURL
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchNearbyEvents(lat: Double, lng: Double, radius: Double = 50000) async throws -> [Event] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/mobile/events/nearby"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius", value: String(radius))
        ]
        guard let url = components.url else { throw APIError.invalidURL }
        let response: EventsResponse = try await request(url: url)
        return response.events
    }

    func fetchAttendingEvents() async throws -> [Event] {
        let url = baseURL.appendingPathComponent("api/v1/mobile/events/attending")
        let response: EventsResponse = try await request(url: url)
        return response.events
    }

    func fetchEventDetail(slug: String) async throws -> Event {
        let url = baseURL.appendingPathComponent("api/v1/mobile/events/\(slug)")
        let response: EventDetailResponse = try await request(url: url)
        return response.event
    }

    func fetchProfile() async throws -> UserProfile {
        let url = baseURL.appendingPathComponent("api/v1/mobile/profile")
        let response: ProfileResponse = try await request(url: url)
        return response.user
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Attach Clerk JWT for authenticated requests
        if let token = try? await Clerk.shared.auth.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code): return "Server error (HTTP \(code))"
        case .decodingError(let error): return "Data error: \(error.localizedDescription)"
        }
    }
}
