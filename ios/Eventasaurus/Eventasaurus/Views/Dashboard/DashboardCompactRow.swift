import SwiftUI

/// Compact row for dashboard events — thumbnail + title/details + role badge.
struct DashboardCompactRow: View {
    let event: DashboardEvent
    let isPast: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            thumbnail
            details
            Spacer(minLength: 0)
            EventRoleBadge(role: event.role)
        }
        .padding(DS.Spacing.lg)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .opacity(isPast ? 0.6 : 1.0)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        if let urlStr = event.coverImageUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderImage
                case .empty:
                    Rectangle().foregroundStyle(.quaternary).overlay { ProgressView() }
                @unknown default:
                    placeholderImage
                }
            }
            .frame(width: DS.ImageSize.thumbnail, height: DS.ImageSize.thumbnail)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        } else {
            placeholderImage
                .frame(width: DS.ImageSize.thumbnail, height: DS.ImageSize.thumbnail)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }

    private var placeholderImage: some View {
        Rectangle()
            .foregroundStyle(.quaternary)
            .overlay {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(event.title)
                .font(DS.Typography.bodyMedium)
                .lineLimit(1)

            HStack(spacing: DS.Spacing.xs) {
                if let startsAt = event.startsAt {
                    Text(startsAt, format: .dateTime.hour().minute())
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if event.startsAt != nil, (event.venue != nil || event.isVirtual) {
                    Text("·")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if let venue = event.venue {
                    Text(venue.name)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if event.isVirtual {
                    Text("Online")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
