import SwiftUI

/// Compact row layout: thumbnail(60pt) | title + time·venue | trailing badge.
/// Generic over any `EventDisplayable` model. Accepts a trailing badge via `@ViewBuilder`.
struct EventCompactRow<Item: EventDisplayable, TrailingBadge: View>: View {
    let event: Item
    var isPast: Bool? = nil
    @ViewBuilder let trailingBadge: () -> TrailingBadge

    private var resolvedIsPast: Bool {
        isPast ?? event.displayIsPast
    }

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            thumbnail
            details
            Spacer(minLength: 0)
            trailingBadge()
        }
        .padding(DS.Spacing.lg)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .opacity(resolvedIsPast ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        CachedImage(
            url: AppConfig.resolvedImageURL(event.displayCoverImageUrl),
            height: DS.ImageSize.thumbnail,
            cornerRadius: DS.Radius.md,
            placeholderIcon: "calendar"
        )
        .frame(width: DS.ImageSize.thumbnail, height: DS.ImageSize.thumbnail)
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(event.displayTitle)
                .font(DS.Typography.bodyMedium)
                .lineLimit(1)

            HStack(spacing: DS.Spacing.xs) {
                if let startsAt = event.displayStartsAt {
                    Text(startsAt, format: .dateTime.hour().minute())
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if event.displayStartsAt != nil, event.displayVenueName != nil {
                    Text("\u{00B7}")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if let venue = event.displayVenueName {
                    Text(venue)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        var parts = [event.displayTitle]
        if let date = event.displayStartsAt {
            parts.append(date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
        }
        if let venue = event.displayVenueName {
            parts.append(venue)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Convenience Init (no trailing badge)

extension EventCompactRow where TrailingBadge == EmptyView {
    init(event: Item, isPast: Bool? = nil) {
        self.event = event
        self.isPast = isPast
        self.trailingBadge = { EmptyView() }
    }
}
