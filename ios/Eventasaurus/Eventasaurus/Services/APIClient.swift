import Foundation
import ClerkKit

@Observable
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session = URLSession.shared
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    static let defaultBaseURL = AppConfig.apiBaseURL

    init(baseURL: URL = defaultBaseURL) {
        self.baseURL = baseURL
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
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
        perPage: Int = 20,
        language: String? = nil
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

        if let language, language != "en" {
            queryItems.append(URLQueryItem(name: "language", value: language))
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

    func fetchEventDetail(slug: String) async throws -> Event {
        let url = baseURL.appendingPathComponent("api/v1/mobile/events/\(slug)")
        let response: EventDetailResponse = try await request(url: url)
        return response.event
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

    func fetchVenueDetail(slug: String) async throws -> VenueDetailResponse {
        let url = baseURL.appendingPathComponent("api/v1/mobile/venues/\(slug)")
        return try await request(url: url)
    }

    // MARK: - Private

    /// Shared helper: attaches auth token, executes request, validates response, returns raw data.
    private func performRequest(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        #if DEBUG
        let devAuth = await MainActor.run { (DevAuthService.shared.isDevAuthActive, DevAuthService.shared.selectedUserId) }
        if devAuth.0, let userId = devAuth.1 {
            request.setValue(userId, forHTTPHeaderField: "X-Dev-User-Id")
        } else if let token = try? await Clerk.shared.auth.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #else
        if let token = try? await Clerk.shared.auth.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #endif

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let body = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }

    private func request<T: Decodable>(url: URL) async throws -> T {
        let data = try await performRequest(URLRequest(url: url))
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func request<T: Decodable, B: Encodable>(url: URL, method: String, body: B) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try self.encoder.encode(body)

        let data = try await performRequest(urlRequest)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func request<T: Decodable>(url: URL, method: String) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method

        let data = try await performRequest(urlRequest)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

enum APIError: Error, LocalizedError, CustomDebugStringConvertible {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code, _): return "Server error (HTTP \(code))"
        case .decodingError(let error): return "Data error: \(error.localizedDescription)"
        }
    }

    var debugDescription: String {
        switch self {
        case .httpError(let code, let body):
            if let body, !body.isEmpty {
                return "APIError.httpError(\(code)): \(body)"
            }
            return "APIError.httpError(\(code))"
        default:
            return errorDescription ?? String(describing: self)
        }
    }
}
