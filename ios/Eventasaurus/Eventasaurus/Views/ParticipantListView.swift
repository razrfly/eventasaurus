import SwiftUI

/// Organizer view showing all participants for an event with filtering,
/// swipe-to-delete, and resend invitation capabilities.
struct ParticipantListView: View {
    let event: UserEvent
    var onParticipantsChanged: (() -> Void)?

    @State private var participants: [EventParticipant] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var selectedFilter: ParticipantFilter = .all
    @State private var showInviteSheet = false
    @State private var participantToRemove: EventParticipant?

    enum ParticipantFilter: String, CaseIterable, Identifiable {
        case all, going, interested, pending
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: return "All"
            case .going: return "Going"
            case .interested: return "Interested"
            case .pending: return "Pending"
            }
        }

        /// Maps to raw DB status for filtering
        var rawStatus: String? {
            switch self {
            case .all: return nil
            case .going: return "accepted"
            case .interested: return "interested"
            case .pending: return "pending"
            }
        }
    }

    private var filteredParticipants: [EventParticipant] {
        guard let status = selectedFilter.rawStatus else { return participants }
        return participants.filter { $0.rawStatus == status }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterChips
            participantList
        }
        .navigationTitle("Participants")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInviteSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await loadParticipants() }
        .refreshable { await loadParticipants() }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "Something went wrong")
        }
        .alert("Remove Participant", isPresented: Binding(
            get: { participantToRemove != nil },
            set: { if !$0 { participantToRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let participant = participantToRemove {
                    Task { await removeParticipant(participant) }
                }
            }
            Button("Cancel", role: .cancel) {
                participantToRemove = nil
            }
        } message: {
            if let p = participantToRemove {
                Text("Remove \(p.user?.name ?? p.email ?? "this participant") from the event?")
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteGuestsSheet(event: event) { count in
                if count > 0 {
                    Task { await loadParticipants() }
                    onParticipantsChanged?()
                }
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.md) {
                ForEach(ParticipantFilter.allCases) { filter in
                    chipButton(filter)
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.md)
        }
    }

    private func chipButton(_ filter: ParticipantFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count: Int = {
            if filter == .all { return participants.count }
            guard let status = filter.rawStatus else { return 0 }
            return participants.filter { $0.rawStatus == status }.count
        }()

        return Button {
            withAnimation(DS.Animation.fast) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(filter.displayName)
                Text("\(count)")
                    .font(DS.Typography.badge)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(isSelected ? .white.opacity(0.3) : Color.secondary.opacity(0.15))
                    )
            }
            .font(DS.Typography.captionMedium)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Participant List

    @ViewBuilder
    private var participantList: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredParticipants.isEmpty {
            EmptyStateView(
                icon: "person.2.slash",
                title: "No Participants",
                message: selectedFilter == .all
                    ? "No one has joined this event yet. Invite some friends!"
                    : "No participants with this status.",
                actionTitle: selectedFilter == .all ? "Invite Guests" : nil,
                action: selectedFilter == .all ? { showInviteSheet = true } : nil
            )
        } else {
            List {
                Section {
                    ForEach(filteredParticipants) { participant in
                        participantRow(participant)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    participantToRemove = participant
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                let emailStatus = EmailDeliveryStatus(from: participant.emailStatus)
                                if emailStatus == .failed || emailStatus == .bounced {
                                    Button {
                                        Task { await resendInvitation(participant) }
                                    } label: {
                                        Label("Resend Invitation", systemImage: "arrow.clockwise")
                                    }
                                }

                                Button(role: .destructive) {
                                    participantToRemove = participant
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("\(filteredParticipants.count) participant\(filteredParticipants.count == 1 ? "" : "s")")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Participant Row

    private func participantRow(_ participant: EventParticipant) -> some View {
        HStack(spacing: DS.Spacing.lg) {
            // Avatar
            DiceBearAvatar(
                email: participant.email ?? participant.user?.email ?? participant.id,
                size: 44
            )
            .clipShape(Circle())

            // Name + email
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(participant.user?.name ?? participant.email ?? "Unknown")
                    .font(DS.Typography.bodyMedium)
                    .lineLimit(1)

                if let email = participant.email ?? participant.user?.email {
                    Text(email)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status pill + email status
            VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                statusPill(for: participant)
                emailStatusIcon(for: participant)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func statusPill(for participant: EventParticipant) -> some View {
        let (text, color) = statusDisplay(rawStatus: participant.rawStatus)
        return Text(text)
            .font(DS.Typography.badge)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func statusDisplay(rawStatus: String) -> (String, Color) {
        switch rawStatus {
        case "accepted": return ("Going", DS.Colors.going)
        case "interested": return ("Interested", DS.Colors.interested)
        case "pending": return ("Pending", .secondary)
        case "declined": return ("Declined", DS.Colors.error)
        case "cancelled": return ("Cancelled", DS.Colors.error)
        default: return (rawStatus.capitalized, .secondary)
        }
    }

    @ViewBuilder
    private func emailStatusIcon(for participant: EventParticipant) -> some View {
        let status = EmailDeliveryStatus(from: participant.emailStatus)
        if status != .notSent {
            HStack(spacing: DS.Spacing.xxs) {
                Image(systemName: status.icon)
                    .font(.system(size: 10))
                Text(status.displayName)
                    .font(.system(size: 10))
            }
            .foregroundStyle(status.color)
        }
    }

    // MARK: - Data

    private func loadParticipants() async {
        do {
            participants = try await GraphQLClient.shared.fetchEventParticipants(slug: event.slug)
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    private func removeParticipant(_ participant: EventParticipant) async {
        guard let userId = participant.user?.id else { return }
        do {
            try await GraphQLClient.shared.removeParticipant(slug: event.slug, userId: userId)
            participants.removeAll { $0.id == participant.id }
            onParticipantsChanged?()
        } catch {
            self.error = error
        }
    }

    private func resendInvitation(_ participant: EventParticipant) async {
        guard let userId = participant.user?.id else { return }
        do {
            try await GraphQLClient.shared.resendInvitation(slug: event.slug, userId: userId)
            // Refresh to get updated email status
            await loadParticipants()
        } catch {
            self.error = error
        }
    }
}
