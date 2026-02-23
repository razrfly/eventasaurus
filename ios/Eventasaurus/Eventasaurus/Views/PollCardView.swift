import SwiftUI

struct PollCardView: View {
    let poll: EventPoll
    let slug: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(poll.title)
                        .font(DS.Typography.bodyBold)
                    if let description = poll.description {
                        Text(description)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                phaseBadge
                Image(systemName: "chevron.right")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.tertiary)
            }

            // Voting deadline
            if let deadline = poll.votingDeadline {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Typography.caption)
                    Text(deadline > Date() ? "Voting ends \(deadline, format: .relative(presentation: .named))" : "Voting closed")
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(.secondary)
            }

            // Options summary
            let maxVotes = poll.options.map(\.voteCount).max() ?? 1
            ForEach(poll.options) { option in
                let isMyVote = poll.myVotes?.contains(where: { $0.optionId == option.id }) ?? false

                HStack(spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(option.title)
                            .font(isMyVote ? DS.Typography.bodyMedium : DS.Typography.body)
                            .foregroundStyle(isMyVote ? Color.accentColor : .primary)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isMyVote ? Color.accentColor : Color.secondary.opacity(0.3))
                                    .frame(width: maxVotes > 0 ? geo.size.width * CGFloat(option.voteCount) / CGFloat(maxVotes) : 0, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }

                    Text("\(option.voteCount)")
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Components

    private var phaseBadge: some View {
        Text(phaseName)
            .font(DS.Typography.micro)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(phaseColor.opacity(0.15))
            .foregroundStyle(phaseColor)
            .clipShape(Capsule())
    }

    private var phaseName: String {
        switch poll.phase {
        case "list_building": return "Building"
        case "voting_with_suggestions": return "Voting"
        case "voting_only": return "Voting"
        case "closed": return "Closed"
        default: return poll.phase.capitalized
        }
    }

    private var phaseColor: Color {
        switch poll.phase {
        case "closed": return .secondary
        case "list_building": return .orange
        default: return .blue
        }
    }
}
