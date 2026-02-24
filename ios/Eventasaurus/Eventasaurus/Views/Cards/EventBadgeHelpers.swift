import SwiftUI

// MARK: - Shared Helpers

/// Status badge used by both Dashboard and UserEvent contexts.
/// White text on status-colored background, matching Discover badge style.
private func eventStatusBadge(_ status: EventStatus) -> some View {
    HStack(spacing: DS.Spacing.xxs) {
        Image(systemName: status.icon)
        Text(status.displayName)
    }
    .badgeStyle(backgroundColor: status.color.opacity(DS.Opacity.badge))
}

// MARK: - Discover Badges

/// Badge builders for the Discover tab (used with `Event` items).
enum DiscoverBadges {

    /// Category pill: emoji icon + name, colored background.
    static func categoryBadge(_ category: Category) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            if let icon = category.icon {
                Text(icon)
                    .font(DS.Typography.micro)
            }
            Text(category.name)
                .font(DS.Typography.badge)
        }
        .badgeStyle(backgroundColor: category.resolvedColor.opacity(DS.Opacity.badge))
    }

    /// Time badge: green background.
    static func timeBadge(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.badge)
            .badgeStyle(backgroundColor: DS.Colors.success.opacity(DS.Opacity.badge))
    }

    /// Group badge: glass style, handles movie_group / event_group / container_group.
    /// - Parameter compact: When true, shows shorter labels (just counts).
    @ViewBuilder
    static func groupBadge(for event: Event, compact: Bool = false) -> some View {
        if let (icon, label) = groupBadgeContent(for: event, compact: compact) {
            HStack(spacing: compact ? DS.Spacing.xxs : DS.Spacing.xs) {
                Image(systemName: icon)
                Text(label)
            }
            .font(DS.Typography.badge)
            .glassBadgeStyle()
        }
    }

    private static func groupBadgeContent(for event: Event, compact: Bool) -> (String, String)? {
        switch event.type {
        case "movie_group":
            guard let count = event.screeningCount, count > 0 else { return nil }
            return ("film", compact ? "\(count)" : "\(count) screening\(count == 1 ? "" : "s")")
        case "event_group":
            guard let count = event.eventCount, count > 0 else { return nil }
            return ("rectangle.stack", compact ? "\(count)" : "\(count) event\(count == 1 ? "" : "s")")
        case "container_group":
            let label = event.containerType ?? "festival"
            return ("sparkles", label.capitalized)
        default:
            return nil
        }
    }
}

// MARK: - Dashboard Badges

/// Badge builders for the My Events / Dashboard tab (used with `DashboardEvent` items).
enum DashboardBadges {

    static func statusBadge(_ status: EventStatus) -> some View {
        eventStatusBadge(status)
    }
}

// MARK: - User Event Badges

/// Badge builders for `UserEvent` items (event management views).
enum UserEventBadges {

    static func statusBadge(_ status: EventStatus) -> some View {
        eventStatusBadge(status)
    }

    /// Visibility badge.
    static func visibilityBadge(_ visibility: EventVisibility) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: visibility.icon)
            Text(visibility.displayName)
        }
        .font(DS.Typography.badge)
        .glassBadgeStyle()
    }

    /// RSVP badge.
    static func rsvpBadge(_ status: RsvpStatus) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: status.icon)
            Text(status.displayName)
        }
        .font(DS.Typography.badge)
        .badgeStyle(backgroundColor: rsvpColor(status).opacity(DS.Opacity.badge))
    }

    private static func rsvpColor(_ status: RsvpStatus) -> Color {
        switch status {
        case .going: return DS.Colors.going
        case .interested: return DS.Colors.interested
        case .notGoing: return .gray
        }
    }
}
