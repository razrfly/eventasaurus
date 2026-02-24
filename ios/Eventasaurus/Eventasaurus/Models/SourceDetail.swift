import Foundation

struct SourceDetailResponse: Decodable {
    let source: SourceInfo
    let events: [Event]
    let availableCities: [SourceCity]?
}

struct SourceInfo: Codable {
    let name: String
    let slug: String
    let logoUrl: String?
    let websiteUrl: String?
    let eventCount: Int?
    let domains: [String]?
}

struct SourceCity: Codable, Identifiable {
    let id: Int
    let name: String
    let slug: String
}
