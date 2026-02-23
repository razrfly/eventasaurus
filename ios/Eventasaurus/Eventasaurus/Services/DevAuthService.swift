#if DEBUG
import Foundation

@MainActor @Observable
final class DevAuthService {
    static let shared = DevAuthService()

    private let defaults = UserDefaults.standard
    private let userIdKey = "dev_auth_user_id"
    private let userNameKey = "dev_auth_user_name"

    var isDevAuthActive: Bool { selectedUserId != nil }
    private(set) var selectedUserId: String?
    private(set) var selectedUserName: String?

    var users: DevQuickLoginUsers?
    var isLoadingUsers = false

    init() {
        selectedUserId = defaults.string(forKey: userIdKey)
        selectedUserName = defaults.string(forKey: userNameKey)
    }

    func selectUser(id: String, name: String) {
        selectedUserId = id
        selectedUserName = name
        defaults.set(id, forKey: userIdKey)
        defaults.set(name, forKey: userNameKey)
    }

    func clearDevAuth() {
        selectedUserId = nil
        selectedUserName = nil
        defaults.removeObject(forKey: userIdKey)
        defaults.removeObject(forKey: userNameKey)
        users = nil
    }

    func fetchUsers() async {
        isLoadingUsers = true
        defer { isLoadingUsers = false }

        do {
            users = try await GraphQLClient.shared.fetchDevQuickLoginUsers()
        } catch {
            print("DevAuth: Failed to fetch users: \(error)")
        }
    }
}

// MARK: - Models

struct DevQuickLoginUsers: Decodable {
    let personal: [DevUser]
    let organizers: [DevUser]
    let participants: [DevUser]
}

struct DevUser: Decodable, Identifiable {
    let id: String
    let name: String?
    let email: String
    let label: String
}

struct GQLDevQuickLoginUsersResponse: Decodable {
    let devQuickLoginUsers: DevQuickLoginUsers
}
#endif
