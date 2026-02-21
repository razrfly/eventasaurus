import SwiftUI

/// Card component for user-created/managed events (from GraphQL API).
/// Mirrors EventCardView's layout but works with the UserEvent model
/// and shows management-relevant info (status, participant count, organizer badge).
struct UserEventCardView: View {
    let event: UserEvent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Cover image with status badge
            ZStack(alignment: .topLeading) {
                if let url = event.coverImageUrl.flatMap({ URL(string: $0) }) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .foregroundStyle(.quaternary)
                            .overlay {
                                Image(systemName: "calendar")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                    .frame(height: DS.ImageSize.cardCover)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .foregroundStyle(.quaternary)
                        .frame(height: DS.ImageSize.cardCover)
                        .overlay {
                            Image(systemName: "calendar")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                        }
                }

                // Status + visibility badges
                HStack {
                    statusBadge
                    Spacer()
                    visibilityBadge
                }
                .padding(DS.Spacing.md)
            }

            // Title
            Text(event.title)
                .font(DS.Typography.heading)
                .lineLimit(2)

            // Tagline
            if let tagline = event.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(DS.Typography.bodyItalic)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Date
            if let date = event.startsAt {
                Label {
                    Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                } icon: {
                    Image(systemName: "clock")
                }
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
            }

            // Venue or Virtual
            if event.isVirtual {
                Label("Virtual Event", systemImage: "video")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            } else if let venue = event.venue {
                Label(venue.name, systemImage: "mappin")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Bottom row: participant count + RSVP status
            HStack {
                if event.participantCount > 0 {
                    Label("\(event.participantCount)", systemImage: "person.2")
                        .font(DS.Typography.captionMedium)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let rsvp = event.myRsvpStatus {
                    rsvpBadge(rsvp)
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Badges

    private var statusBadge: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: event.status.icon)
            Text(event.status.displayName)
        }
        .font(DS.Typography.badge)
        .badgeStyle(backgroundColor: statusColor.opacity(DS.Opacity.badge))
    }

    private var statusColor: Color {
        switch event.status {
        case .draft: return .orange
        case .confirmed: return .green
        case .canceled: return .red
        case .polling: return .blue
        case .threshold: return .purple
        }
    }

    private var visibilityBadge: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: event.visibility.icon)
            Text(event.visibility.displayName)
        }
        .font(DS.Typography.badge)
        .glassBadgeStyle()
    }

    private func rsvpBadge(_ status: RsvpStatus) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: status.icon)
            Text(status.displayName)
        }
        .font(DS.Typography.badge)
        .badgeStyle(backgroundColor: rsvpColor(status).opacity(DS.Opacity.badge))
    }

    private func rsvpColor(_ status: RsvpStatus) -> Color {
        switch status {
        case .going: return DS.Colors.going
        case .interested: return DS.Colors.interested
        case .notGoing: return .gray
        }
    }

    private var accessibilityText: String {
        var parts = [event.title]
        parts.append(event.status.displayName)
        if let date = event.startsAt {
            parts.append(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        }
        if let venue = event.venue {
            parts.append(venue.name)
        }
        if event.participantCount > 0 {
            parts.append("\(event.participantCount) participants")
        }
        return parts.joined(separator: ", ")
    }
}
