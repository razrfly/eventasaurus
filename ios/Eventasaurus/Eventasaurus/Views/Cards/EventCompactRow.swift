import SwiftUI

/// Compact row layout: thumbnail(60pt) | category + title + time·venue | trailing badge.
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
            // Line 1: Category emoji + name (when available)
            if let categoryName = event.displayPrimaryCategoryName {
                HStack(spacing: DS.Spacing.xs) {
                    if let icon = event.displayPrimaryCategoryIcon {
                        Text(icon)
                            .font(DS.Typography.caption)
                    }
                    Text(categoryName)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Line 2-3: Title (up to 2 lines)
            Text(event.displayTitle)
                .font(DS.Typography.bodyMedium)
                .lineLimit(2)

            // Line 4: clock + time · mappin + venue
            metadataLine
        }
    }

    // MARK: - Metadata Line

    @ViewBuilder
    private var metadataLine: some View {
        let hasTime = event.displayStartsAt != nil
        let hasVenue = event.displayVenueName != nil

        if hasTime || hasVenue {
            HStack(spacing: DS.Spacing.xs) {
                if let startsAt = event.displayStartsAt {
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: "clock")
                        Text(startsAt, format: .dateTime.hour().minute())
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                }

                if hasTime && hasVenue {
                    Text("\u{00B7}")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if let venue = event.displayVenueName {
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(venue)
                            .lineLimit(1)
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        var parts: [String] = []
        if let categoryName = event.displayPrimaryCategoryName {
            parts.append(categoryName)
        }
        parts.append(event.displayTitle)
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
