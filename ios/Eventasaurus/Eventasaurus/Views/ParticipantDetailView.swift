import SwiftUI

/// Detail view for a single event participant, showing info and actions
/// for organizers: change status, resend invitation, remove.
struct ParticipantDetailView: View {
    let event: UserEvent
    let participant: EventParticipant
    var onChanged: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: RsvpStatus
    @State private var isUpdatingStatus = false
    @State private var isResending = false
    @State private var showRemoveAlert = false
    @State private var isRemoving = false
    @State private var error: Error?
    @State private var showSuccess: String?

    init(event: UserEvent, participant: EventParticipant, onChanged: (() -> Void)? = nil) {
        self.event = event
        self.participant = participant
        self.onChanged = onChanged
        self._selectedStatus = State(initialValue: participant.status)
    }

    private var displayName: String {
        participant.user?.name ?? participant.email ?? "Unknown"
    }

    private var displayEmail: String? {
        participant.email ?? participant.user?.email
    }

    private var emailStatus: EmailDeliveryStatus {
        EmailDeliveryStatus(from: participant.emailStatus)
    }

    private var isOrganizer: Bool {
        participant.role == "organizer"
    }

    var body: some View {
        List {
            headerSection
            infoSection
            if !isOrganizer {
                statusSection
                actionsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Participant")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "Something went wrong")
        }
        .alert("Remove Participant", isPresented: $showRemoveAlert) {
            Button("Remove", role: .destructive) {
                Task { await removeParticipant() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(displayName) from the event? This cannot be undone.")
        }
        .overlay {
            if let message = showSuccess {
                successToast(message)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: DS.Spacing.lg) {
                DiceBearAvatar(
                    email: displayEmail ?? participant.id,
                    size: DS.ImageSize.avatarLarge
                )
                .clipShape(Circle())

                VStack(spacing: DS.Spacing.xs) {
                    Text(displayName)
                        .font(DS.Typography.title)

                    if let email = displayEmail {
                        Text(email)
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section("Details") {
            infoRow(label: "Role", value: isOrganizer ? "Organizer" : "Invitee", icon: isOrganizer ? "star.fill" : "person.fill")

            HStack {
                Label("Status", systemImage: "circle.fill")
                    .font(DS.Typography.body)
                Spacer()
                statusPill(rawStatus: participant.rawStatus)
            }

            if emailStatus != .notSent {
                HStack {
                    Label("Email", systemImage: emailStatus.icon)
                        .font(DS.Typography.body)
                    Spacer()
                    Text(emailStatus.displayName)
                        .font(DS.Typography.body)
                        .foregroundStyle(emailStatus.color)
                }
            }

            if let invitedAt = participant.invitedAt {
                infoRow(label: "Invited", value: invitedAt.formatted(date: .abbreviated, time: .shortened), icon: "envelope.fill")
            }

            infoRow(label: "Joined", value: participant.createdAt.formatted(date: .abbreviated, time: .shortened), icon: "calendar")

            if let message = participant.invitationMessage, !message.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Label("Invitation Message", systemImage: "text.bubble")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(DS.Typography.body)
                }
                .padding(.vertical, DS.Spacing.xs)
            }
        }
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(DS.Typography.body)
            Spacer()
            Text(value)
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status Change

    private var statusSection: some View {
        Section("Change Status") {
            Picker("Status", selection: $selectedStatus) {
                ForEach(RsvpStatus.allCases, id: \.self) { status in
                    Label(status.displayName, systemImage: status.icon)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .disabled(isUpdatingStatus)
            .onChange(of: selectedStatus) { _, newStatus in
                if newStatus != participant.status {
                    Task { await updateStatus(newStatus) }
                }
            }

            if isUpdatingStatus {
                HStack {
                    Spacer()
                    ProgressView("Updating...")
                        .font(DS.Typography.caption)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                Task { await resendInvitation() }
            } label: {
                HStack {
                    Label("Resend Invitation", systemImage: "arrow.clockwise")
                    Spacer()
                    if isResending {
                        ProgressView()
                    }
                }
            }
            .disabled(isResending)

            Button(role: .destructive) {
                showRemoveAlert = true
            } label: {
                HStack {
                    Label("Remove Participant", systemImage: "trash")
                    Spacer()
                    if isRemoving {
                        ProgressView()
                    }
                }
            }
            .disabled(isRemoving)
        }
    }

    // MARK: - Status Pill

    private func statusPill(rawStatus: String) -> some View {
        let (text, color) = statusDisplay(rawStatus: rawStatus)
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

    // MARK: - Success Toast

    private func successToast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(DS.Typography.bodyMedium)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.lg)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, DS.Spacing.jumbo)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(DS.Animation.standard, value: showSuccess)
    }

    // MARK: - Actions

    private func updateStatus(_ status: RsvpStatus) async {
        guard let userId = participant.user?.id else {
            selectedStatus = participant.status
            self.error = ParticipantActionError.noUserAccount
            return
        }
        isUpdatingStatus = true
        do {
            try await GraphQLClient.shared.updateParticipantStatus(
                slug: event.slug, userId: userId, status: status
            )
            onChanged?()
            showTemporarySuccess("Status updated")
        } catch {
            selectedStatus = participant.status
            self.error = error
        }
        isUpdatingStatus = false
    }

    private func resendInvitation() async {
        guard let userId = participant.user?.id else {
            self.error = ParticipantActionError.noUserAccount
            return
        }
        isResending = true
        do {
            try await GraphQLClient.shared.resendInvitation(slug: event.slug, userId: userId)
            onChanged?()
            showTemporarySuccess("Invitation sent")
        } catch {
            self.error = error
        }
        isResending = false
    }

    private func removeParticipant() async {
        guard let userId = participant.user?.id else {
            self.error = ParticipantActionError.noUserAccount
            return
        }
        isRemoving = true
        do {
            try await GraphQLClient.shared.removeParticipant(slug: event.slug, userId: userId)
            onChanged?()
            dismiss()
        } catch {
            self.error = error
            isRemoving = false
        }
    }

    private func showTemporarySuccess(_ message: String) {
        withAnimation { showSuccess = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSuccess = nil }
        }
    }
}
