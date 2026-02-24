import Foundation

enum EventViewMode: String, CaseIterable {
    case compact, card, grid

    var icon: String {
        switch self {
        case .compact: return "list.bullet"
        case .card: return "rectangle.grid.1x2"
        case .grid: return "square.grid.2x2"
        }
    }

    /// Cycles compact → card → grid → compact
    var next: EventViewMode {
        switch self {
        case .compact: return .card
        case .card: return .grid
        case .grid: return .compact
        }
    }

    static func load(key: String, default defaultMode: EventViewMode) -> EventViewMode {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return defaultMode }
        return EventViewMode(rawValue: raw) ?? defaultMode
    }

    func save(key: String) {
        UserDefaults.standard.set(rawValue, forKey: key)
    }
}
