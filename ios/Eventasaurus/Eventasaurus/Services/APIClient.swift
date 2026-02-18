import Foundation
import ClerkKit

@Observable
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session = URLSession.shared
    private let decoder: JSONDecoder

    #if DEBUG
    static let defaultBaseURL = URL(string: "http://localhost:4000")!
    #else
    static let defaultBaseURL = URL(string: "https://eventasaur.us")!
    #endif

    init(baseURL: URL = defaultBaseURL) {
        self.baseURL = baseURL
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchNearbyEvents(
        lat: Double? = nil,
        lng: Double? = nil,
        radius: Double = 50000,
        cityId: Int? = nil,
        categoryIds: [Int] = [],
        search: String? = nil,
        dateRange: String? = nil,
        sortBy: String? = nil,
        sortOrder: String? = nil,
        page: Int = 1,
        perPage: Int = 20
    ) async throws -> EventsResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/mobile/events/nearby"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []

        if let cityId {
            queryItems.append(URLQueryItem(name: "city_id", value: String(cityId)))
        } else if let lat, let lng {
            queryItems.append(URLQueryItem(name: "lat", value: String(lat)))
            queryItems.append(URLQueryItem(name: "lng", value: String(lng)))
            queryItems.append(URLQueryItem(name: "radius", value: String(radius)))
        }

        if !categoryIds.isEmpty {
            queryItems.append(URLQueryItem(name: "categories", value: categoryIds.map(String.init).joined(separator: ",")))
        }

        if let search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }

        if let dateRange {
            queryItems.append(URLQueryItem(name: "date_range", value: dateRange))
        }

        if let sortBy {
            queryItems.append(URLQueryItem(name: "sort_by", value: sortBy))
        }

        if let sortOrder {
            queryItems.append(URLQueryItem(name: "sort_order", value: sortOrder))
        }

        queryItems.append(URLQueryItem(name: "page", value: String(page)))
        queryItems.append(URLQueryItem(name: "per_page", value: String(perPage)))

        components.queryItems = queryItems
        guard let url = components.url else { throw APIError.invalidURL }
        return try await request(url: url)
    }

    func fetchCategories() async throws -> [Category] {
        let url = baseURL.appendingPathComponent("api/v1/mobile/categories")
        let response: CategoriesResponse = try await request(url: url)
        return response.categories
    }

    func searchCities(query: String? = nil) async throws -> [City] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/mobile/cities"), resolvingAgainstBaseURL: false)!
        if let query, !query.isEmpty {
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        guard let url = components.url else { throw APIError.invalidURL }
        let response: CitiesResponse = try await request(url: url)
        return response.cities
    }

    func fetchPopularCities() async throws -> [City] {
        let url = baseURL.appendingPathComponent("api/v1/mobile/cities/popular")
        let response: CitiesResponse = try await request(url: url)
        return response.cities
    }

    func resolveCity(lat: Double, lng: Double) async throws -> City {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/mobile/cities/resolve"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng))
        ]
        guard let url = components.url else { throw APIError.invalidURL }
        let response: CityResolveResponse = try await request(url: url)
        return response.city
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

    func fetchMovieDetail(slug: String, cityId: Int? = nil) async throws -> MovieDetailResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/mobile/movies/\(slug)"), resolvingAgainstBaseURL: false)!
        if let cityId {
            components.queryItems = [URLQueryItem(name: "city_id", value: String(cityId))]
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return try await request(url: url)
    }

    func fetchSourceDetail(slug: String, cityId: Int? = nil) async throws -> SourceDetailResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/mobile/sources/\(slug)"), resolvingAgainstBaseURL: false)!
        if let cityId {
            components.queryItems = [URLQueryItem(name: "city_id", value: String(cityId))]
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return try await request(url: url)
    }

    func fetchContainerDetail(slug: String) async throws -> ContainerDetailResponse {
        let url = baseURL.appendingPathComponent("api/v1/mobile/containers/\(slug)")
        return try await request(url: url)
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
