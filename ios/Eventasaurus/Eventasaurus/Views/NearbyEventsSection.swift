import SwiftUI

struct NearbyEventsSection: View {
    let events: [Event]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Nearby Events")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.lg) {
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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            CachedImage(
                url: event.coverImageUrl.flatMap { URL(string: $0) },
                height: DS.ImageSize.carouselItem,
                cornerRadius: DS.Radius.md
            )
            .frame(width: DS.ImageSize.carouselItemWidth)

            Text(event.title)
                .font(DS.Typography.captionBold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let date = event.startsAt {
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(DS.Typography.micro)
                    .foregroundStyle(.secondary)
            }

            if let venue = event.venue {
                Text(venue.displayName)
                    .font(DS.Typography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: DS.ImageSize.carouselItemWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nearbyEventAccessibilityLabel(event))
    }

    private func nearbyEventAccessibilityLabel(_ event: Event) -> String {
        var parts = [event.title]
        if let date = event.startsAt {
            parts.append(date.formatted(.dateTime.month(.abbreviated).day()))
        }
        if let venue = event.venue {
            parts.append(venue.displayName)
        }
        return parts.joined(separator: ", ")
    }
}
