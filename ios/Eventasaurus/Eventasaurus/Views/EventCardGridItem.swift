import SwiftUI

struct EventCardGridItem: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cover image with badges — taller aspect for grid
            ZStack(alignment: .topLeading) {
                CachedImage(
                    url: event.coverImageUrl.flatMap { URL(string: $0) },
                    height: 200,
                    placeholderIcon: event.isGroup ? "square.stack" : "calendar"
                )

                // Badge overlay
                HStack {
                    // Category badge (top-left)
                    if let category = event.primaryCategory, !event.isGroup {
                        gridCategoryBadge(category)
                    }

                    Spacer()

                    // Group badge or time badge (top-right)
                    if event.isGroup {
                        gridGroupBadge
                    } else if let badge = timeBadgeText {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.9))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(6)
            }

            // Title (2 lines max)
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            // Date
            if let date = event.startsAt, !event.isGroup {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let subtitle = event.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }

    // MARK: - Category Badge (compact)

    private func gridCategoryBadge(_ category: Category) -> some View {
        HStack(spacing: 2) {
            if let icon = category.icon {
                Text(icon)
                    .font(.system(size: 9))
            }
            Text(category.name)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(category.resolvedColor.opacity(0.9))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }

    // MARK: - Group Badge (compact)

    @ViewBuilder
    private var gridGroupBadge: some View {
        if let (icon, label) = groupBadgeContent {
            HStack(spacing: 2) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }

    private var groupBadgeContent: (String, String)? {
        switch event.type {
        case "movie_group":
            let count = event.screeningCount ?? 0
            return ("film", "\(count)")
        case "event_group":
            let count = event.eventCount ?? 0
            return ("rectangle.stack", "\(count)")
        case "container_group":
            let label = event.containerType ?? "festival"
            return ("sparkles", label.capitalized)
        default:
            return nil
        }
    }

    private var timeBadgeText: String? {
        guard let startsAt = event.startsAt, !event.isGroup else { return nil }
        let interval = startsAt.timeIntervalSince(Date())
        if interval < 0 { return nil }
        if interval < 3600 { return "Soon" }
        if Calendar.current.isDateInToday(startsAt) { return "Today" }
        if Calendar.current.isDateInTomorrow(startsAt) { return "Tomorrow" }
        return nil
    }
}
