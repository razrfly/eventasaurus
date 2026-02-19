import Foundation

struct PlanResponse: Codable {
    let plan: PlanInfo?
}

struct PlanInfo: Codable, Identifiable {
    var id: String { slug }
    let slug: String
    let title: String
    let createdAt: String?
    let inviteCount: Int?
}

struct CreatePlanRequest: Encodable {
    let emails: [String]
    let message: String?
    let occurrence: PlanOccurrence?
}

struct PlanOccurrence: Codable {
    let venueName: String?
    let datetime: String?
}

struct ParticipantStatusResponse: Codable {
    let status: String?
    let participantCount: Int?
    let updatedAt: String?
    let removed: Bool?
}
