import SwiftUI

/// Grid card layout: cover image (200pt) with badge overlays | title (2 lines) | subtitle content.
/// Generic over any `EventDisplayable` model. Accepts `@ViewBuilder` closures for badges and subtitle.
struct EventGridCard<Item: EventDisplayable, CoverBadges: View, SubtitleContent: View>: View {
    let event: Item
    var isPast: Bool? = nil
    @ViewBuilder let coverBadges: () -> CoverBadges
    @ViewBuilder let subtitleContent: () -> SubtitleContent

    private var resolvedIsPast: Bool {
        isPast ?? event.displayIsPast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Cover image with badge overlay
            ZStack(alignment: .topLeading) {
                CachedImage(
                    url: AppConfig.resolvedImageURL(event.displayCoverImageUrl),
                    height: DS.ImageSize.gridCover,
                    placeholderIcon: "calendar"
                )

                coverBadges()
                    .padding(DS.Spacing.sm)
            }

            // Title (2 lines max)
            Text(event.displayTitle)
                .font(DS.Typography.bodyMedium)
                .lineLimit(2)
                .padding(.horizontal, DS.Spacing.md)

            // Subtitle content
            subtitleContent()
                .padding(.horizontal, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.md)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .dsShadow(DS.Shadow.cardLight)
        .opacity(resolvedIsPast ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        var parts = [event.displayTitle]
        if let date = event.displayStartsAt {
            parts.append(date.formatted(.dateTime.month(.wide).day()))
        }
        if let tagline = event.displayTagline {
            parts.append(tagline)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Convenience Init (no badges)

extension EventGridCard where CoverBadges == EmptyView, SubtitleContent == EmptyView {
    init(event: Item, isPast: Bool? = nil) {
        self.event = event
        self.isPast = isPast
        self.coverBadges = { EmptyView() }
        self.subtitleContent = { EmptyView() }
    }
}
