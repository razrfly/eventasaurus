import SwiftUI

struct StarVotingView: View {
    @Binding var poll: EventPoll
    let slug: String
    @Binding var isVoting: Bool
    @Binding var error: String?

    @State private var selectedScores: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(poll.options) { option in
                optionCard(option)
            }
        }
    }

    private func optionCard(_ option: PollOption) -> some View {
        let existingVote = poll.myVotes?.first(where: { $0.optionId == option.id })
        let hasVoted = existingVote != nil
        let maxVotes = poll.options.map(\.voteCount).max() ?? 1

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(option.title)
                    .font(DS.Typography.bodyBold)
                Spacer()
                if let avg = option.averageScore {
                    Text(String(format: "%.1f", avg))
                        .font(DS.Typography.captionBold)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xxs)
                        .background(Color.yellow.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }

            if let desc = option.description, !desc.isEmpty {
                Text(desc)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if hasVoted {
                // Locked stars showing the user's vote
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(DS.Typography.caption)

                    let score = existingVote?.score ?? 0
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= score ? "star.fill" : "star")
                                .foregroundStyle(star <= score ? .yellow : .secondary)
                        }
                    }
                    .font(.title3)

                    Text("Rated")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Star picker
                let score = selectedScores[option.id] ?? 0

                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= score ? "star.fill" : "star")
                            .foregroundStyle(star <= score ? .yellow : .secondary)
                            .onTapGesture { selectedScores[option.id] = star }
                    }
                }
                .font(.title3)

                if score > 0 {
                    Button {
                        Task { await vote(for: option, score: score) }
                    } label: {
                        Text("Rate")
                            .font(DS.Typography.bodyMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.vertical, DS.Spacing.sm)
                            .background(Color.accentColor)
                            .cornerRadius(DS.Radius.md)
                    }
                    .buttonStyle(.plain)
                    .disabled(isVoting)
                }
            }

            // Vote bar
            HStack {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(hasVoted ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: maxVotes > 0 ? geo.size.width * CGFloat(option.voteCount) / CGFloat(maxVotes) : 0, height: 4)
                    }
                }
                .frame(height: 4)

                Text("\(option.voteCount)")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func vote(for option: PollOption, score: Int) async {
        isVoting = true
        error = nil

        do {
            try await GraphQLClient.shared.voteOnPoll(
                pollId: poll.id,
                optionId: option.id,
                score: score
            )
        } catch {
            self.error = error.localizedDescription
            isVoting = false
            return
        }

        await refreshPoll()
        isVoting = false
    }

    private func refreshPoll() async {
        do {
            let polls = try await GraphQLClient.shared.fetchEventPolls(slug: slug)
            if let updated = polls.first(where: { $0.id == poll.id }) {
                poll = updated
            }
        } catch {
            #if DEBUG
            print("[StarVotingView] Poll refresh failed: \(error)")
            #endif
        }
    }
}
