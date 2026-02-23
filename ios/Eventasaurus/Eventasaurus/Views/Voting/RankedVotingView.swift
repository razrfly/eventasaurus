import SwiftUI

struct RankedVotingView: View {
    @Binding var poll: EventPoll
    let slug: String
    @Binding var isVoting: Bool
    @Binding var error: String?

    @State private var orderedOptions: [PollOption] = []
    @State private var hasSubmitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if hasSubmitted || hasExistingRanks {
                submittedView
            } else {
                rankingView
            }
        }
        .onAppear {
            initializeOrder()
        }
    }

    private var hasExistingRanks: Bool {
        guard let votes = poll.myVotes else { return false }
        return votes.contains(where: { $0.voteRank != nil })
    }

    // MARK: - Ranking View (before submission)

    private var rankingView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Drag to reorder your preferences")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(orderedOptions.enumerated()), id: \.element.id) { index, option in
                    HStack(spacing: DS.Spacing.md) {
                        Text("#\(index + 1)")
                            .font(DS.Typography.bodyBold)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(option.title)
                                .font(DS.Typography.body)
                            if let desc = option.description, !desc.isEmpty {
                                Text(desc)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text("\(option.voteCount)")
                            .font(DS.Typography.captionBold)
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: DS.Spacing.sm, leading: DS.Spacing.md, bottom: DS.Spacing.sm, trailing: DS.Spacing.md))
                }
                .onMove { from, to in
                    orderedOptions.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: CGFloat(orderedOptions.count) * 60)
            .environment(\.editMode, .constant(.active))

            Button {
                Task { await submitRanking() }
            } label: {
                HStack {
                    Spacer()
                    if isVoting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Submit Ranking")
                    }
                    Spacer()
                }
                .font(DS.Typography.bodyMedium)
                .foregroundStyle(.white)
                .padding(.vertical, DS.Spacing.md)
                .background(Color.accentColor)
                .cornerRadius(DS.Radius.md)
            }
            .disabled(isVoting)
        }
    }

    // MARK: - Submitted View

    private var submittedView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ranking submitted")
                    .font(DS.Typography.bodyMedium)
            }

            let rankedOptions = buildRankedOptions()
            ForEach(Array(rankedOptions.enumerated()), id: \.element.id) { index, option in
                HStack(spacing: DS.Spacing.md) {
                    Text("#\(index + 1)")
                        .font(DS.Typography.bodyBold)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32)

                    Text(option.title)
                        .font(DS.Typography.body)

                    Spacer()

                    Text("\(option.voteCount)")
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DS.Spacing.xs)
            }

            Button {
                Task { await clearAndRevote() }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Re-rank")
                }
                .font(DS.Typography.caption)
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isVoting)
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func initializeOrder() {
        if let votes = poll.myVotes, votes.contains(where: { $0.voteRank != nil }) {
            // Restore saved ranking order
            orderedOptions = poll.options.sorted { a, b in
                let rankA = votes.first(where: { $0.optionId == a.id })?.voteRank ?? Int.max
                let rankB = votes.first(where: { $0.optionId == b.id })?.voteRank ?? Int.max
                return rankA < rankB
            }
        } else {
            orderedOptions = poll.options
        }
    }

    private func buildRankedOptions() -> [PollOption] {
        guard let votes = poll.myVotes else { return orderedOptions }
        return poll.options.sorted { a, b in
            let rankA = votes.first(where: { $0.optionId == a.id })?.voteRank ?? Int.max
            let rankB = votes.first(where: { $0.optionId == b.id })?.voteRank ?? Int.max
            return rankA < rankB
        }
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
        hasSubmitted = false
        await refreshPoll()
        initializeOrder()
        isVoting = false
    }

    private func submitRanking() async {
        isVoting = true
        error = nil

        do {
            // Clear any existing votes first so retries after partial failure are idempotent
            try await GraphQLClient.shared.clearMyPollVotes(pollId: poll.id)

            for (index, option) in orderedOptions.enumerated() {
                try await GraphQLClient.shared.voteOnPoll(
                    pollId: poll.id,
                    optionId: option.id,
                    score: index + 1
                )
            }
        } catch {
            self.error = error.localizedDescription
            isVoting = false
            return
        }

        await refreshPoll()
        hasSubmitted = true
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
            print("[RankedVotingView] Poll refresh failed: \(error)")
            #endif
        }
    }
}
