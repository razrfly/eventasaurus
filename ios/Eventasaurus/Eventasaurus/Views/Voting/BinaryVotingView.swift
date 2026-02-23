import SwiftUI

struct BinaryVotingView: View {
    @Binding var poll: EventPoll
    let slug: String
    @Binding var isVoting: Bool
    @Binding var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(poll.options) { option in
                optionCard(option)
            }
        }
    }

    private func optionCard(_ option: PollOption) -> some View {
        let existingVote = poll.myVotes?.first(where: { $0.optionId == option.id })
        let maxVotes = poll.options.map(\.voteCount).max() ?? 1

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(option.title)
                .font(DS.Typography.bodyBold)

            if let desc = option.description, !desc.isEmpty {
                Text(desc)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            // Vote buttons
            HStack(spacing: DS.Spacing.sm) {
                voteButton(option: option, value: "yes", icon: "hand.thumbsup", color: .green, existingVote: existingVote)
                voteButton(option: option, value: "maybe", icon: "hand.raised", color: .orange, existingVote: existingVote)
                voteButton(option: option, value: "no", icon: "hand.thumbsdown", color: .red, existingVote: existingVote)
                Spacer()
                Text("\(option.voteCount)")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(.secondary)
            }

            // Vote bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(existingVote != nil ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: maxVotes > 0 ? geo.size.width * CGFloat(option.voteCount) / CGFloat(maxVotes) : 0, height: 4)
                }
            }
            .frame(height: 4)
        }
        .cardStyle()
    }

    private func voteButton(option: PollOption, value: String, icon: String, color: Color, existingVote: PollVote?) -> some View {
        let isSelected = existingVote?.voteValue == value
        let hasVoted = existingVote != nil

        return Button {
            Task { await vote(for: option, value: value) }
        } label: {
            Image(systemName: isSelected ? "\(icon).fill" : icon)
                .font(DS.Typography.body)
                .foregroundStyle(isSelected ? .white : hasVoted ? .secondary : color)
                .frame(width: 40, height: 36)
                .background(isSelected ? color : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? color : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isVoting || hasVoted)
    }

    private func vote(for option: PollOption, value: String) async {
        isVoting = true
        error = nil

        do {
            try await GraphQLClient.shared.voteOnPoll(
                pollId: poll.id,
                optionId: option.id,
                voteValue: value
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
            print("[BinaryVotingView] Poll refresh failed: \(error)")
            #endif
        }
    }
}
