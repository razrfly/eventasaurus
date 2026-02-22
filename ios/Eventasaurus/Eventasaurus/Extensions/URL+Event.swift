import Foundation

extension URL {
    static func event(slug: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wombie.com"
        components.path = "/events/\(slug)"
        return components.url
    }
}
