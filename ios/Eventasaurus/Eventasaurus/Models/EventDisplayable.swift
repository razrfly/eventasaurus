import Foundation

/// Unified protocol for displaying events across different data models.
/// Conformers: `Event`, `DashboardEvent`, `UserEvent`.
protocol EventDisplayable: Identifiable, Hashable {
    var displaySlug: String { get }
    var displayTitle: String { get }
    var displayTagline: String? { get }
    var displayStartsAt: Date? { get }
    var displayEndsAt: Date? { get }
    var displayCoverImageUrl: String? { get }
    var displayVenueName: String? { get }
    var displayIsVirtual: Bool { get }
    var displayParticipantCount: Int? { get }
    var displayIsPast: Bool { get }
    var displayPrimaryCategoryIcon: String? { get }
    var displayPrimaryCategoryName: String? { get }
}

// MARK: - Defaults

extension EventDisplayable {
    var displayTagline: String? { nil }
    var displayIsVirtual: Bool { false }
    var displayParticipantCount: Int? { nil }
    var displayPrimaryCategoryIcon: String? { nil }
    var displayPrimaryCategoryName: String? { nil }

    var displayIsPast: Bool {
        guard let date = displayEndsAt ?? displayStartsAt else { return false }
        return date < Date()
    }
}
