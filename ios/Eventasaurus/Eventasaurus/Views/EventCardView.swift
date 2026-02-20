import SwiftUI

struct EventCardView: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Cover image with badges
            ZStack(alignment: .topLeading) {
                CachedImage(
                    url: event.coverImageUrl.flatMap { URL(string: $0) },
                    height: DS.ImageSize.cardCover,
                    placeholderIcon: event.isGroup ? "square.stack" : "calendar"
                )

                // Badge overlay
                HStack {
                    // Category badge (top-left)
                    if let category = event.primaryCategory, !event.isGroup {
                        categoryBadge(category)
                    }

                    Spacer()

                    // Group badge or time badge (top-right)
                    if event.isGroup {
                        groupBadge
                    } else if let badge = timeBadgeText {
                        timeBadge(badge)
                    }
                }
                .padding(DS.Spacing.md)
            }

            // Title
            Text(event.title)
                .font(DS.Typography.heading)
                .lineLimit(2)

            // Subtitle for aggregated groups
            if let subtitle = event.subtitle {
                Text(subtitle)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            } else {
                // Date for regular events
                if let date = event.startsAt {
                    Text(date, style: .date)
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                }

                // Venue for regular events
                if let venue = event.venue {
                    Label(venue.name, systemImage: "mappin")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(eventAccessibilityLabel)
    }

    private var eventAccessibilityLabel: String {
        var parts = [event.title]
        if let date = event.startsAt {
            parts.append(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        }
        if let venue = event.venue {
            parts.append(venue.name)
        }
        if let subtitle = event.subtitle {
            parts.append(subtitle)
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Category Badge

    private func categoryBadge(_ category: Category) -> some View {
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

    // MARK: - Time Badge

    private func timeBadge(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.badge)
            .badgeStyle(backgroundColor: DS.Colors.success.opacity(DS.Opacity.badge))
    }

    // MARK: - Time Badge Text

    private var timeBadgeText: String? {
        guard let startsAt = event.startsAt, !event.isGroup else { return nil }
        let interval = startsAt.timeIntervalSince(Date())
        if interval < 0 { return nil }
        if interval < 3600 { return "Starting soon" }
        if Calendar.current.isDateInToday(startsAt) { return "Today" }
        if Calendar.current.isDateInTomorrow(startsAt) { return "Tomorrow" }
        return nil
    }

    // MARK: - Group Badge

    @ViewBuilder
    private var groupBadge: some View {
        if let (icon, label) = groupBadgeContent {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                Text(label)
            }
            .font(DS.Typography.badge)
            .glassBadgeStyle()
        }
    }

    private var groupBadgeContent: (String, String)? {
        switch event.type {
        case "movie_group":
            let count = event.screeningCount ?? 0
            return ("film", "\(count) screening\(count == 1 ? "" : "s")")
        case "event_group":
            let count = event.eventCount ?? 0
            return ("rectangle.stack", "\(count) event\(count == 1 ? "" : "s")")
        case "container_group":
            let label = event.containerType ?? "festival"
            return ("sparkles", label.capitalized)
        default:
            return nil
        }
    }
}
