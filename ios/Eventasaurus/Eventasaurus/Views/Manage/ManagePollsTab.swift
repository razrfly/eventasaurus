import SwiftUI

/// Polls tab showing event polls with status-dependent empty states.
struct ManagePollsTab: View {
    let polls: [EventPoll]
    let slug: String
    let eventId: String
    let eventStatus: EventStatus
    let onRefresh: () async -> Void

    @State private var showCreateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if !polls.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    ForEach(polls) { poll in
                        NavigationLink {
                            PollDetailView(poll: poll, slug: slug, isOrganizer: true)
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

            if canCreatePoll {
                Button {
                    showCreateSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Poll")
                    }
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(Color.accentColor)
                    .cornerRadius(DS.Radius.md)
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xl)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            PollCreateSheet(eventId: eventId) {
                await onRefresh()
            }
        }
    }

    private var canCreatePoll: Bool {
        eventStatus == .polling || eventStatus == .threshold
    }

    @ViewBuilder
    private var emptyState: some View {
        if eventStatus == .polling || eventStatus == .threshold {
            EmptyStateView(
                icon: "chart.bar",
                title: "No Polls Yet",
                message: "Create a poll to let attendees vote on options for this event."
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
