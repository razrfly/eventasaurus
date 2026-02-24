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

            // Line 4: clock + time · mappin + venue, movie TMDB data, or group metadata
            if event.displayStartsAt != nil || event.displayVenueName != nil {
                metadataLine
            } else if event.displayMovieRating != nil || event.displayMovieRuntime != nil || event.displayMovieGenres != nil {
                movieMetadataLine
            } else if let metadata = event.displayCompactMetadata {
                Text(metadata)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            // Line 5 (optional): tagline for movies with TMDB data
            if let tag = event.displayCompactTagline {
                Text(tag)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .italic()
            }
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
                        Text(startsAt.smartEventFormat())
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

    // MARK: - Movie Metadata Line

    @ViewBuilder
    private var movieMetadataLine: some View {
        let segments: [(icon: String, text: String)] = [
            event.displayMovieRating.map { rating in
                let formatted = rating.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", rating)
                    : String(format: "%.1f", rating)
                return ("popcorn.fill", formatted)
            },
            event.displayMovieRuntime.map { ("hourglass", "\($0) min") },
            event.displayMovieGenres.map { ("theatermasks.fill", $0) }
        ].compactMap { $0 }

        if !segments.isEmpty {
            HStack(spacing: DS.Spacing.xs) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Text("\u{00B7}")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: DS.Spacing.xxs) {
                        Image(systemName: segment.icon)
                        Text(segment.text)
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

        // Movie group metadata for VoiceOver (rating, runtime, genres, tagline)
        if let rating = event.displayMovieRating {
            let formatted = rating.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", rating)
                : String(format: "%.1f", rating)
            parts.append("rated \(formatted) out of 10")
        }
        if let runtime = event.displayMovieRuntime {
            parts.append("\(runtime) minutes")
        }
        if let genres = event.displayMovieGenres, !genres.isEmpty {
            parts.append(genres)
        }
        if let tagline = event.displayCompactTagline, !tagline.isEmpty {
            parts.append(tagline)
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
