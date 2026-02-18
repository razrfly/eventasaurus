import SwiftUI

struct EventCardView: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image with badges
            ZStack(alignment: .topLeading) {
                CachedImage(
                    url: event.coverImageUrl.flatMap { URL(string: $0) },
                    height: 160,
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
                .padding(8)
            }

            // Title
            Text(event.title)
                .font(.headline)
                .lineLimit(2)

            // Subtitle for aggregated groups (e.g. "12 screenings across 3 venues")
            if let subtitle = event.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Date for regular events
                if let date = event.startsAt {
                    Text(date, style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Venue for regular events
                if let venue = event.venue {
                    Label(venue.name, systemImage: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: - Category Badge

    private func categoryBadge(_ category: Category) -> some View {
        HStack(spacing: 3) {
            if let icon = category.icon {
                Text(icon)
                    .font(.caption2)
            }
            Text(category.name)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(category.resolvedColor.opacity(0.9))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }

    // MARK: - Time Badge

    private func timeBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.green.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    // MARK: - Time Badge Text (view-level concern, not model)

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
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
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
