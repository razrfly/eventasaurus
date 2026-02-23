import SwiftUI

/// Card view for dashboard events — cover image + details + role badge.
struct DashboardCardView: View {
    let event: DashboardEvent
    let isPast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            coverImage
            eventDetails
        }
        .cardStyle()
        .opacity(isPast ? 0.6 : 1.0)
    }

    // MARK: - Cover Image

    @ViewBuilder
    private var coverImage: some View {
        ZStack(alignment: .topLeading) {
            if let url = AppConfig.resolvedImageURL(event.coverImageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderCover
                    case .empty:
                        Rectangle().foregroundStyle(.quaternary).overlay { ProgressView() }
                    @unknown default:
                        placeholderCover
                    }
                }
                .frame(height: DS.ImageSize.cardCover)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            } else {
                placeholderCover
            }

            // Status badge overlay
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: event.status.icon)
                Text(event.status.displayName)
            }
            .font(DS.Typography.badge)
            .badgeStyle(backgroundColor: event.status.color.opacity(DS.Opacity.badge), foregroundColor: event.status.color)
            .padding(DS.Spacing.md)
        }
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg)
            .foregroundStyle(.quaternary)
            .frame(height: DS.ImageSize.cardCover)
            .overlay {
                Image(systemName: "calendar")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Event Details

    private var eventDetails: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(event.title)
                .font(DS.Typography.heading)
                .lineLimit(2)

            if let tagline = event.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(DS.Typography.bodyItalic)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: DS.Spacing.xs) {
                if let startsAt = event.startsAt {
                    Label {
                        Text(startsAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let venue = event.venue {
                Label(venue.name ?? "Unknown Venue", systemImage: "mappin")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if event.isVirtual {
                Label("Online", systemImage: "video")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("\(event.participantCount)", systemImage: "person.2")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                EventRoleBadge(role: event.role)
            }
        }
    }

}
