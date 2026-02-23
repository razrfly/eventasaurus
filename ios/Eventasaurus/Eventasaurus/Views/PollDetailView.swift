import SwiftUI

struct PollDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let slug: String
    let isOrganizer: Bool
    @State private var localPoll: EventPoll
    @State private var isVoting = false
    @State private var error: String?
    @State private var showSuggestSheet = false
    @State private var stats: PollVotingStats?

    // Phase 4: Admin state
    @State private var showDeleteConfirmation = false
    @State private var isPerformingAction = false

    init(poll: EventPoll, slug: String, isOrganizer: Bool = false) {
        self.slug = slug
        self.isOrganizer = isOrganizer
        _localPoll = State(initialValue: poll)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                header
                if isOrganizer {
                    adminControls
                }
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
        .toolbar {
            if canSuggest {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSuggestSheet = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showSuggestSheet) {
            SuggestOptionSheet(pollId: localPoll.id) {
                await refreshPoll()
            }
        }
        .alert("Delete Poll", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await deletePoll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the poll and all votes. This cannot be undone.")
        }
        .task {
            if localPoll.isClosed {
                await loadStats()
            }
        }
    }

    private var canSuggest: Bool {
        localPoll.phase == "list_building" || localPoll.phase == "voting_with_suggestions"
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

    // MARK: - Admin Controls (Phase 4)

    private var adminControls: some View {
        VStack(spacing: DS.Spacing.sm) {
            // Phase transition buttons
            HStack(spacing: DS.Spacing.sm) {
                if localPoll.phase == "list_building" {
                    phaseButton(label: "Start Voting", phase: "voting_only", color: .blue)
                    phaseButton(label: "Voting + Suggestions", phase: "voting_with_suggestions", color: .blue)
                } else if localPoll.phase == "voting_with_suggestions" {
                    phaseButton(label: "Lock Suggestions", phase: "voting_only", color: .blue)
                    phaseButton(label: "Close Poll", phase: "closed", color: .secondary)
                } else if localPoll.phase == "voting_only" {
                    phaseButton(label: "Close Poll", phase: "closed", color: .secondary)
                }
            }

            // Delete button
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "trash")
                    Text("Delete Poll")
                }
                .font(DS.Typography.caption)
            }
            .disabled(isPerformingAction)
        }
        .padding(DS.Spacing.md)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(DS.Radius.md)
    }

    private func phaseButton(label: String, phase: String, color: Color) -> some View {
        Button {
            Task { await transitionPhase(to: phase) }
        } label: {
            Text(label)
                .font(DS.Typography.captionMedium)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .cornerRadius(DS.Radius.sm)
        }
        .buttonStyle(.plain)
        .disabled(isPerformingAction)
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
        } else if let stats {
            richResultsSection(stats)
        } else {
            closedResultsSection
        }
    }

    // MARK: - Simple Closed Results (fallback)

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

    // MARK: - Rich Results (Phase 5)

    private func richResultsSection(_ stats: PollVotingStats) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack {
                Text("Results")
                    .font(DS.Typography.bodyBold)
                Spacer()
                Text("\(stats.totalUniqueVoters) voter\(stats.totalUniqueVoters == 1 ? "" : "s")")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            switch stats.votingSystem {
            case "binary":
                binaryResults(stats)
            case "approval":
                approvalResults(stats)
            case "star":
                starResults(stats)
            case "ranked":
                rankedResults(stats)
            default:
                closedResultsSection
            }
        }
    }

    private func binaryResults(_ stats: PollVotingStats) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(stats.options) { opt in
                let total = (opt.tally.yes ?? 0) + (opt.tally.maybe ?? 0) + (opt.tally.no ?? 0)
                let isMyVote = localPoll.myVotes?.contains(where: { $0.optionId == opt.optionId }) ?? false

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(opt.optionTitle)
                        .font(isMyVote ? DS.Typography.bodyMedium : DS.Typography.bodyBold)
                        .foregroundStyle(isMyVote ? Color.accentColor : .primary)

                    if total > 0 {
                        HStack(spacing: 1) {
                            voteBar(count: opt.tally.yes ?? 0, total: total, color: .green, label: "Yes")
                            voteBar(count: opt.tally.maybe ?? 0, total: total, color: .orange, label: "Maybe")
                            voteBar(count: opt.tally.no ?? 0, total: total, color: .red, label: "No")
                        }
                        .frame(height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack(spacing: DS.Spacing.md) {
                            voteLegend(color: .green, label: "Yes", count: opt.tally.yes ?? 0)
                            voteLegend(color: .orange, label: "Maybe", count: opt.tally.maybe ?? 0)
                            voteLegend(color: .red, label: "No", count: opt.tally.no ?? 0)
                        }
                    } else {
                        Text("No votes")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .cardStyle()
            }
        }
    }

    private func approvalResults(_ stats: PollVotingStats) -> some View {
        let sorted = stats.options.sorted { ($0.tally.selected ?? 0) > ($1.tally.selected ?? 0) }
        let maxSelected = sorted.first.flatMap { $0.tally.selected } ?? 1

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(sorted) { opt in
                let count = opt.tally.selected ?? 0
                let pct = opt.tally.percentage ?? 0
                let isMyVote = localPoll.myVotes?.contains(where: { $0.optionId == opt.optionId }) ?? false

                HStack(spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(opt.optionTitle)
                            .font(isMyVote ? DS.Typography.bodyMedium : DS.Typography.body)
                            .foregroundStyle(isMyVote ? Color.accentColor : .primary)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isMyVote ? Color.accentColor : .blue)
                                    .frame(width: maxSelected > 0 ? geo.size.width * CGFloat(count) / CGFloat(maxSelected) : 0, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }

                    Text("\(count) (\(String(format: "%.0f", pct))%)")
                        .font(DS.Typography.captionBold)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
            }
        }
        .cardStyle()
    }

    private func starResults(_ stats: PollVotingStats) -> some View {
        let sorted = stats.options.sorted { ($0.tally.averageScore ?? 0) > ($1.tally.averageScore ?? 0) }

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(sorted) { opt in
                let avg = opt.tally.averageScore ?? 0
                let count = opt.tally.total ?? 0
                let isMyVote = localPoll.myVotes?.contains(where: { $0.optionId == opt.optionId }) ?? false

                HStack(spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(opt.optionTitle)
                            .font(isMyVote ? DS.Typography.bodyMedium : DS.Typography.body)
                            .foregroundStyle(isMyVote ? Color.accentColor : .primary)

                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: Double(star) <= avg ? "star.fill" : (Double(star) - 0.5 <= avg ? "star.leadinghalf.filled" : "star"))
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                        Text(String(format: "%.1f", avg))
                            .font(DS.Typography.bodyBold)
                            .foregroundStyle(.orange)
                        Text("\(count) ratings")
                            .font(DS.Typography.micro)
                            .foregroundStyle(.secondary)
                    }
                }
                .cardStyle()
            }
        }
    }

    private func rankedResults(_ stats: PollVotingStats) -> some View {
        let sorted = stats.options.sorted { ($0.tally.averageRank ?? Double.infinity) < ($1.tally.averageRank ?? Double.infinity) }

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, opt in
                let avgRank = opt.tally.averageRank ?? 0
                let firstPlace = opt.tally.firstPlaceCount ?? 0
                let isMyVote = localPoll.myVotes?.contains(where: { $0.optionId == opt.optionId }) ?? false

                HStack(spacing: DS.Spacing.md) {
                    Text("#\(index + 1)")
                        .font(DS.Typography.bodyBold)
                        .foregroundStyle(index == 0 ? Color.accentColor : .secondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(opt.optionTitle)
                            .font(isMyVote ? DS.Typography.bodyMedium : DS.Typography.body)
                            .foregroundStyle(isMyVote ? Color.accentColor : .primary)
                        Text("Avg rank: \(String(format: "%.1f", avgRank)) \u{2022} \(firstPlace) first-place")
                            .font(DS.Typography.micro)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .cardStyle()
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func voteBar(count: Int, total: Int, color: Color, label: String) -> some View {
        if count > 0 {
            color
                .frame(width: nil)
                .layoutPriority(Double(count))
                .accessibilityLabel("\(label): \(count)")
        }
    }

    private func voteLegend(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(DS.Typography.micro)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func transitionPhase(to phase: String) async {
        isPerformingAction = true
        error = nil
        do {
            try await GraphQLClient.shared.transitionPollPhase(pollId: localPoll.id, phase: phase)
            await refreshPoll()
            if phase == "closed" {
                await loadStats()
            }
        } catch {
            self.error = error.localizedDescription
        }
        isPerformingAction = false
    }

    private func deletePoll() async {
        isPerformingAction = true
        do {
            try await GraphQLClient.shared.deletePoll(pollId: localPoll.id)
            isPerformingAction = false
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isPerformingAction = false
        }
    }

    private func loadStats() async {
        do {
            stats = try await GraphQLClient.shared.fetchPollStats(pollId: localPoll.id)
        } catch {
            #if DEBUG
            print("[PollDetailView] Failed to load stats: \(error)")
            #endif
        }
    }

    private func refreshPoll() async {
        do {
            let polls = try await GraphQLClient.shared.fetchEventPolls(slug: slug)
            if let updated = polls.first(where: { $0.id == localPoll.id }) {
                localPoll = updated
            }
        } catch {
            #if DEBUG
            print("[PollDetailView] Poll refresh failed: \(error)")
            #endif
        }
    }
}
