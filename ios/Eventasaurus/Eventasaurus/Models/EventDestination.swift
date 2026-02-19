import Foundation

enum EventDestination: Hashable {
    case event(slug: String)
    case movieGroup(slug: String, cityId: Int?)
    case eventGroup(slug: String, cityId: Int?)
    case containerGroup(slug: String)
    case venue(slug: String)
}

extension Event {
    func destination(cityId: Int?) -> EventDestination {
        switch type {
        case "movie_group":
            return .movieGroup(slug: slug, cityId: cityId)
        case "event_group":
            return .eventGroup(slug: slug, cityId: cityId)
        case "container_group":
            return .containerGroup(slug: slug)
        default:
            return .event(slug: slug)
        }
    }
}
