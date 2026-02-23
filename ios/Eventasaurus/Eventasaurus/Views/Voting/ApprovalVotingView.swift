import SwiftUI

struct ApprovalVotingView: View {
    @Binding var poll: EventPoll
    let slug: String
    @Binding var isVoting: Bool
    @Binding var error: String?

    private var hasAnyApprovals: Bool {
        guard let votes = poll.myVotes else { return false }
        return !votes.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(poll.options) { option in
                optionRow(option)
            }
            if hasAnyApprovals {
                Button {
                    Task { await clearAndRevote() }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Change Votes")
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
                .padding(.top, DS.Spacing.xs)
            }
        }
    }

    private func optionRow(_ option: PollOption) -> some View {
        let isApproved = poll.myVotes?.contains(where: { $0.optionId == option.id }) ?? false
        let maxVotes = poll.options.map(\.voteCount).max() ?? 1

        return Button {
            if !isApproved {
                Task { await vote(for: option) }
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: isApproved ? "checkmark.square.fill" : "square")
                    .font(DS.Typography.body)
                    .foregroundStyle(isApproved ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(option.title)
                        .font(isApproved ? DS.Typography.bodyMedium : DS.Typography.body)
                        .foregroundStyle(isApproved ? Color.accentColor : .primary)

                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isApproved ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: maxVotes > 0 ? geo.size.width * CGFloat(option.voteCount) / CGFloat(maxVotes) : 0, height: 4)
                        }
                    }
                    .frame(height: 4)
                }

                Spacer()

                Text("\(option.voteCount)")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.Spacing.md)
            .background(Color(.systemBackground))
            .cornerRadius(DS.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(isApproved ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isVoting || isApproved)
    }

    private func vote(for option: PollOption) async {
        isVoting = true
        error = nil

        do {
            try await GraphQLClient.shared.voteOnPoll(
                pollId: poll.id,
                optionId: option.id
            )
        } catch {
            self.error = error.localizedDescription
            isVoting = false
            return
        }

        await refreshPoll()
        isVoting = false
    }

    private func clearAndRevote() async {
        isVoting = true
        error = nil
        do {
            try await GraphQLClient.shared.clearMyPollVotes(pollId: poll.id)
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
            print("[ApprovalVotingView] Poll refresh failed: \(error)")
            #endif
        }
    }
}
