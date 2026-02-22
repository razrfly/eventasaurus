import SwiftUI

/// Sheet for inviting guests to an event via email or friend suggestions.
/// Simplified version of PlanWithFriendsSheet for organizer use.
struct InviteGuestsSheet: View {
    let event: UserEvent
    var onInvited: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var emails: [String] = []
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var inviteCount = 0
    @State private var errorMessage: String?

    // Suggestions
    @State private var suggestions: [ParticipantSuggestion] = []
    @State private var isLoadingSuggestions = true
    @State private var selectedFriendIds: Set<String> = []

    // Templates
    @State private var selectedTemplate: MessageTemplate? = nil
    @State private var showTemplates = false

    private let maxMessageLength = 500

    var body: some View {
        NavigationStack {
            Group {
                if showSuccess {
                    successView
                        .transition(.scale.combined(with: .opacity))
                } else {
                    formContent
                }
            }
            .navigationTitle("Invite Guests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await loadSuggestions() }
    }

    // MARK: - Form Content

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                // Friend suggestions
                if isLoadingSuggestions || !suggestions.isEmpty {
                    suggestionsSection
                    Divider()
                }

                emailInputSection

                Divider()

                messageSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.error)
                }

                submitButton
            }
            .padding(DS.Spacing.xl)
        }
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("People from your past events")
                .font(DS.Typography.bodyMedium)
            Text("Select people who have attended your previous events")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)

            if isLoadingSuggestions {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, DS.Spacing.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.md) {
                        ForEach(suggestions) { suggestion in
                            suggestionCard(suggestion)
                        }
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
        }
    }

    private func suggestionCard(_ suggestion: ParticipantSuggestion) -> some View {
        let isSelected = selectedFriendIds.contains(suggestion.userId)
        let avatarSize: CGFloat = 48

        return Button {
            toggleSuggestion(suggestion)
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                ZStack(alignment: .bottomTrailing) {
                    DiceBearAvatar(email: suggestion.maskedEmail ?? suggestion.userId, size: avatarSize)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                            .background(Circle().fill(.white).frame(width: 14, height: 14))
                            .offset(x: 2, y: 2)
                    }
                }

                Text(suggestion.name ?? suggestion.username ?? suggestion.maskedEmail ?? "Friend")
                    .font(DS.Typography.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(participationText(suggestion.participationCount))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80)
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }

    private func participationText(_ count: Int) -> String {
        switch count {
        case 0: return "New"
        case 1: return "1 event"
        default: return "\(count) events"
        }
    }

    // MARK: - Email Input

    private var emailInputSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Invite by email")
                .font(DS.Typography.bodyMedium)
            Text("They'll receive an email invitation to the event.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            EmailChipInput(emails: $emails)
        }
    }

    // MARK: - Message

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("Personal message (optional)")
                    .font(DS.Typography.bodyMedium)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTemplates.toggle()
                    }
                } label: {
                    Text(showTemplates ? "Hide templates" : "Use template")
                        .font(DS.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                }
            }

            if showTemplates {
                VStack(spacing: DS.Spacing.sm) {
                    Text("Choose a template:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(MessageTemplate.allCases) { template in
                        templateCard(template)
                    }
                }
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(Color(.systemGray6))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            TextField("Hi! I'd love for you to join me at this event...", text: $message, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .onChange(of: message) { _, newValue in
                    if newValue.count > maxMessageLength {
                        message = String(newValue.prefix(maxMessageLength))
                    }
                }

            HStack {
                Spacer()
                Text("\(message.count)/\(maxMessageLength)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func templateCard(_ template: MessageTemplate) -> some View {
        Button {
            selectedTemplate = template
            message = template.text
            withAnimation(.easeInOut(duration: 0.2)) {
                showTemplates = false
            }
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(template.displayName)
                    .font(DS.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(template.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit

    private var totalInviteCount: Int {
        emails.count + selectedFriendIds.count
    }

    private var submitButton: some View {
        Button {
            Task { await sendInvites() }
        } label: {
            if isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Send Invites (\(totalInviteCount))")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(totalInviteCount == 0 || isSubmitting)
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DS.Colors.success)
            Text("Invites sent!")
                .font(DS.Typography.titleSecondary)
            Text("\(inviteCount) guest\(inviteCount == 1 ? "" : "s") invited to your event.")
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(DS.Spacing.xl)
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            dismiss()
        }
    }

    // MARK: - Data

    private func loadSuggestions() async {
        do {
            suggestions = try await GraphQLClient.shared.fetchParticipantSuggestions(limit: 20)
        } catch {
            // Silently fail — suggestions are optional
        }
        isLoadingSuggestions = false
    }

    private func toggleSuggestion(_ suggestion: ParticipantSuggestion) {
        guard let email = suggestion.maskedEmail else { return }
        if selectedFriendIds.contains(suggestion.userId) {
            selectedFriendIds.remove(suggestion.userId)
            emails.removeAll { $0 == email }
        } else {
            selectedFriendIds.insert(suggestion.userId)
            if !emails.contains(email) {
                emails.append(email)
            }
        }
    }

    private func sendInvites() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            // Collect all emails (from suggestions and manual input)
            let allEmails = emails
            let count = try await GraphQLClient.shared.inviteGuests(
                slug: event.slug,
                emails: allEmails,
                message: message.isEmpty ? nil : message
            )

            inviteCount = count
            onInvited?(count)
            withAnimation(DS.Animation.bouncy) {
                showSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
