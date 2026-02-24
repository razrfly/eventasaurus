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
    /// Short metadata string for compact rows when time/venue aren't available (e.g. groups).
    var displayCompactMetadata: String? { get }
    /// Optional tagline shown below metadata for groups with extra space.
    var displayCompactTagline: String? { get }
    /// TMDB rating (0–10) for movie groups. Nil for non-movie items.
    var displayMovieRating: Double? { get }
    /// Runtime in minutes for movie groups (guardrail: only set when >= 30). Nil otherwise.
    var displayMovieRuntime: Int? { get }
    /// Pre-joined genre string for movie groups (e.g. "Drama, Thriller"). Nil otherwise.
    var displayMovieGenres: String? { get }
}

// MARK: - Defaults

extension EventDisplayable {
    var displayTagline: String? { nil }
    var displayIsVirtual: Bool { false }
    var displayParticipantCount: Int? { nil }
    var displayPrimaryCategoryIcon: String? { nil }
    var displayPrimaryCategoryName: String? { nil }
    var displayCompactMetadata: String? { nil }
    var displayCompactTagline: String? { nil }
    var displayMovieRating: Double? { nil }
    var displayMovieRuntime: Int? { nil }
    var displayMovieGenres: String? { nil }

    var displayIsPast: Bool {
        guard let date = displayEndsAt ?? displayStartsAt else { return false }
        return date < Date()
    }
}
