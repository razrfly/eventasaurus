import Foundation

struct ProfileResponse: Codable {
    let user: UserProfile
}

struct UserProfile: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let username: String?
    let bio: String?
    let avatarUrl: String?
    let profileUrl: String?
}
