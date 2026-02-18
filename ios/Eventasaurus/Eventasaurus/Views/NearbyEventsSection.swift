import SwiftUI

struct NearbyEventsSection: View {
    let events: [Event]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nearby Events")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(events) { event in
                        NavigationLink(value: EventDestination.event(slug: event.slug)) {
                            nearbyEventCard(event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func nearbyEventCard(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedImage(
                url: event.coverImageUrl.flatMap { URL(string: $0) },
                height: 100,
                cornerRadius: 8
            )
            .frame(width: 160)

            Text(event.title)
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let date = event.startsAt {
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let venue = event.venue {
                Text(venue.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 160)
    }
}
