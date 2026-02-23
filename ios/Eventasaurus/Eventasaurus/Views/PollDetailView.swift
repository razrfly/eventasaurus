import SwiftUI

struct PollDetailView: View {
    let poll: EventPoll
    let slug: String
    @State private var localPoll: EventPoll
    @State private var isVoting = false
    @State private var error: String?

    init(poll: EventPoll, slug: String) {
        self.poll = poll
        self.slug = slug
        _localPoll = State(initialValue: poll)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                header
                votingSection
                if let error {
                    Text(error)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(DS.Spacing.xl)
        }
        .navigationTitle(localPoll.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(localPoll.title)
                    .font(DS.Typography.heading)
                Spacer()
                phaseBadge
            }

            if let description = localPoll.description {
                Text(description)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }

            if let deadline = localPoll.votingDeadline {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Typography.caption)
                    Text(deadline > Date() ? "Voting ends \(deadline, format: .relative(presentation: .named))" : "Voting closed")
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

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
        switch localPoll.phase {
        case "list_building": return "Building"
        case "voting_with_suggestions": return "Voting"
        case "voting_only": return "Voting"
        case "closed": return "Closed"
        default: return localPoll.phase.capitalized
        }
    }

    private var phaseColor: Color {
        switch localPoll.phase {
        case "closed": return .secondary
        case "list_building": return .orange
        default: return .blue
        }
    }

    // MARK: - Voting Section

    @ViewBuilder
    private var votingSection: some View {
        if localPoll.isVotingActive {
            switch localPoll.votingSystem {
            case "binary":
                BinaryVotingView(poll: $localPoll, slug: slug, isVoting: $isVoting, error: $error)
            case "approval":
                ApprovalVotingView(poll: $localPoll, slug: slug, isVoting: $isVoting, error: $error)
            case "ranked":
                RankedVotingView(poll: $localPoll, slug: slug, isVoting: $isVoting, error: $error)
            case "star":
                StarVotingView(poll: $localPoll, slug: slug, isVoting: $isVoting, error: $error)
            default:
                Text("Unsupported voting system: \(localPoll.votingSystem)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            closedResultsSection
        }
    }

    private var closedResultsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Results")
                .font(DS.Typography.bodyBold)

            let maxVotes = localPoll.options.map(\.voteCount).max() ?? 1

            ForEach(localPoll.options) { option in
                let isMyVote = localPoll.myVotes?.contains(where: { $0.optionId == option.id }) ?? false

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack {
                        Text(option.title)
                            .font(isMyVote ? DS.Typography.bodyMedium : DS.Typography.body)
                            .foregroundStyle(isMyVote ? Color.accentColor : .primary)
                        Spacer()
                        Text("\(option.voteCount)")
                            .font(DS.Typography.captionBold)
                            .foregroundStyle(.secondary)
                    }

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
            }
        }
        .cardStyle()
    }
}
