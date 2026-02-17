import Foundation

struct CategoriesResponse: Codable {
    let categories: [Category]
}

struct Category: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let icon: String?
    let color: String?
}
