import SwiftUI

struct EventCardView: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image
            ZStack(alignment: .topTrailing) {
                CachedImage(
                    url: event.coverImageUrl.flatMap { URL(string: $0) },
                    height: 160,
                    placeholderIcon: event.isGroup ? "square.stack" : "calendar"
                )

                // Badge for aggregated groups
                if event.isGroup {
                    groupBadge
                        .padding(8)
                }
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
