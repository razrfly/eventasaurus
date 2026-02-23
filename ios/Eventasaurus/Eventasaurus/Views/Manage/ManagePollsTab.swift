import SwiftUI

/// Polls tab showing event polls with status-dependent empty states.
struct ManagePollsTab: View {
    let polls: [EventPoll]
    let slug: String
    let eventStatus: EventStatus

    var body: some View {
        if !polls.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                ForEach(polls) { poll in
                    NavigationLink {
                        PollDetailView(poll: poll, slug: slug)
                    } label: {
                        PollCardView(poll: poll, slug: slug)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.md)
        } else {
            emptyState
                .padding(.top, DS.Spacing.xxl)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if eventStatus == .polling || eventStatus == .threshold {
            EmptyStateView(
                icon: "chart.bar",
                title: "No Polls Yet",
                message: "Polls will appear here once they're created for this event."
            )
        } else {
            EmptyStateView(
                icon: "chart.bar",
                title: "Polls Unavailable",
                message: "Polls are available for events in polling or threshold status."
            )
        }
    }
}
