import SwiftUI

struct PollCardView: View {
    let poll: EventPoll
    let slug: String
    @State private var localPoll: EventPoll
    @State private var isVoting = false
    @State private var error: String?
    @State private var selectedScores: [String: Int] = [:]

    init(poll: EventPoll, slug: String) {
        self.poll = poll
        self.slug = slug
        _localPoll = State(initialValue: poll)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(localPoll.title)
                        .font(DS.Typography.bodyBold)
                    if let description = localPoll.description {
                        Text(description)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                phaseBadge
            }

            // Voting deadline
            if let deadline = localPoll.votingDeadline {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(DS.Typography.caption)
                    Text(deadline > Date() ? "Voting ends \(deadline, format: .relative(presentation: .named))" : "Voting closed")
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(.secondary)
            }

            // Options
            ForEach(localPoll.options) { option in
                optionRow(option)
            }

            if let error {
                Text(error)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.red)
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

    private func optionRow(_ option: PollOption) -> some View {
        let isMyVote = localPoll.myVotes?.contains(where: { $0.optionId == option.id }) ?? false
        let maxVotes = localPoll.options.map(\.voteCount).max() ?? 1

        return HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(option.title)
                    .font(isMyVote ? DS.Typography.bodyMedium : DS.Typography.body)
                    .foregroundStyle(isMyVote ? Color.accentColor : .primary)

                if let desc = option.description, !desc.isEmpty {
                    Text(desc)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                // Star rating picker for star voting system
                if localPoll.votingSystem == "star" && localPoll.isVotingActive && !isMyVote {
                    let score = selectedScores[option.id] ?? 5
                    HStack(spacing: DS.Spacing.xxs) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= score ? "star.fill" : "star")
                                .foregroundStyle(star <= score ? .yellow : .secondary)
                                .onTapGesture { selectedScores[option.id] = star }
                        }
                    }
                    .font(DS.Typography.caption)
                }

                // Vote bar
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

            Spacer()

            Text("\(option.voteCount)")
                .font(DS.Typography.captionBold)
                .foregroundStyle(.secondary)

            if localPoll.isVotingActive {
                Button {
                    Task { await vote(for: option) }
                } label: {
                    Image(systemName: isMyVote ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isMyVote ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isVoting || isMyVote)
            }
        }
    }

    // MARK: - Actions

    private func vote(for option: PollOption) async {
        isVoting = true
        error = nil

        let score: Int? = localPoll.votingSystem == "star" ? (selectedScores[option.id] ?? 5) : nil

        do {
            try await GraphQLClient.shared.voteOnPoll(
                pollId: localPoll.id,
                optionId: option.id,
                score: score
            )
        } catch {
            self.error = error.localizedDescription
            isVoting = false
            return
        }

        // Refresh polls separately — vote already succeeded
        do {
            let polls = try await GraphQLClient.shared.fetchEventPolls(slug: slug)
            if let updated = polls.first(where: { $0.id == localPoll.id }) {
                localPoll = updated
            }
        } catch {
            // Vote succeeded but refresh failed — not a user-facing error
            #if DEBUG
            print("[PollCardView] Poll refresh failed after successful vote: \(error)")
            #endif
        }

        isVoting = false
    }
}
