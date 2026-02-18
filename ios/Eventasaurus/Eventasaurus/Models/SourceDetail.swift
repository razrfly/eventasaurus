import Foundation

struct SourceDetailResponse: Codable {
    let source: SourceInfo
    let events: [Event]
}

struct SourceInfo: Codable {
    let name: String
    let slug: String
    let logoUrl: String?
    let websiteUrl: String?
    let eventCount: Int?
}
