import SwiftUI

/// Standard card layout: cover image (160pt) with badge overlays | title | subtitle content | bottom row.
/// Generic over any `EventDisplayable` model. Accepts `@ViewBuilder` closures for badges and content.
struct EventStandardCard<Item: EventDisplayable, CoverBadges: View, SubtitleContent: View, BottomRow: View>: View {
    let event: Item
    var isPast: Bool? = nil
    var coverHeight: CGFloat = DS.ImageSize.cardCover
    var placeholderIcon: String = "calendar"
    @ViewBuilder let coverBadges: () -> CoverBadges
    @ViewBuilder let subtitleContent: () -> SubtitleContent
    @ViewBuilder let bottomRow: () -> BottomRow

    private var resolvedIsPast: Bool {
        isPast ?? event.displayIsPast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Cover image with badge overlay
            ZStack(alignment: .topLeading) {
                CachedImage(
                    url: AppConfig.resolvedImageURL(event.displayCoverImageUrl),
                    height: coverHeight,
                    placeholderIcon: placeholderIcon
                )

                coverBadges()
                    .padding(DS.Spacing.md)
            }

            // Title
            Text(event.displayTitle)
                .font(DS.Typography.heading)
                .lineLimit(2)

            // Subtitle content
            subtitleContent()

            // Bottom row
            bottomRow()
        }
        .cardStyle()
        .opacity(resolvedIsPast ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        var parts = [event.displayTitle]
        if let date = event.displayStartsAt {
            parts.append(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        }
        if let venue = event.displayVenueName {
            parts.append(venue)
        }
        if let tagline = event.displayTagline {
            parts.append(tagline)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Convenience Init (no bottom row)

extension EventStandardCard where BottomRow == EmptyView {
    init(
        event: Item,
        isPast: Bool? = nil,
        coverHeight: CGFloat = DS.ImageSize.cardCover,
        placeholderIcon: String = "calendar",
        @ViewBuilder coverBadges: @escaping () -> CoverBadges,
        @ViewBuilder subtitleContent: @escaping () -> SubtitleContent
    ) {
        self.event = event
        self.isPast = isPast
        self.coverHeight = coverHeight
        self.placeholderIcon = placeholderIcon
        self.coverBadges = coverBadges
        self.subtitleContent = subtitleContent
        self.bottomRow = { EmptyView() }
    }
}
