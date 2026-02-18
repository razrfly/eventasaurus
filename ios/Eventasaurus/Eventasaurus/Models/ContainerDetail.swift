import Foundation

struct ContainerDetailResponse: Codable {
    let container: ContainerInfo
    let events: [Event]
}

struct ContainerInfo: Codable {
    let title: String
    let slug: String
    let containerType: String
    let description: String?
    let startDate: Date?
    let endDate: Date?
    let coverImageUrl: String?
    let sourceUrl: String?
    let eventCount: Int?
}
