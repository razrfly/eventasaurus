import SwiftUI

struct PlanWithFriendsSheet: View {
    let event: Event
    var onPlanCreated: (GQLPlan) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var emails: [String] = []
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var planAlreadyExisted = false
    @State private var serverInviteCount: Int = 0
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
            .navigationTitle("Plan with Friends")
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
                eventHeader

                Divider()

                // Friend suggestions (hidden if empty and done loading)
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

    // MARK: - Event Header

    private var eventHeader: some View {
        HStack(spacing: DS.Spacing.lg) {
            CachedImage(
                url: AppConfig.resolvedImageURL(event.coverImageUrl),
                height: DS.ImageSize.thumbnail,
                cornerRadius: DS.Radius.md,
                placeholderIcon: "calendar"
            )
            .frame(width: DS.ImageSize.thumbnail)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(event.title)
                    .font(DS.Typography.bodyMedium)
                    .lineLimit(2)
                if let venue = event.venue {
                    Text(venue.displayName)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                if let date = event.startsAt {
                    Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Suggestions Section

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
                // Avatar with selection overlay
                ZStack(alignment: .bottomTrailing) {
                    DiceBearAvatar(
                        url: suggestion.avatarUrl.flatMap { URL(string: $0) },
                        size: avatarSize
                    )
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isSelected ? DS.Colors.plan : .clear, lineWidth: 2.5)
                    )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.Colors.plan)
                            .background(Circle().fill(.white).frame(width: 18, height: 18))
                            .offset(x: 2, y: 2)
                    }
                }

                // Name
                Text(suggestion.name ?? suggestion.username ?? suggestion.maskedEmail ?? "Unknown")
                    .font(DS.Typography.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                // Participation count
                Text(participationText(suggestion.participationCount))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                // Recommendation badge
                if suggestion.recommendationLevel == .highlyRecommended {
                    badgeView(text: "Top pick", color: .green)
                } else if suggestion.recommendationLevel == .recommended {
                    badgeView(text: "Recommended", color: .blue)
                }
            }
            .frame(width: 80)
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isSelected ? DS.Colors.plan.opacity(0.06) : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }

    private func participationText(_ count: Int) -> String {
        switch count {
        case 0: return "New"
        case 1: return "1 event"
        default: return "\(count) events"
        }
    }

    // MARK: - Email Input Section

    private var emailInputSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Invite friends by email")
                .font(DS.Typography.bodyMedium)
            Text("They'll receive an email invitation to join your plan.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            EmailChipInput(emails: $emails)
        }
    }

    // MARK: - Message Section

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
                        .foregroundStyle(DS.Colors.plan)
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

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            Task { await createPlan() }
        } label: {
            if isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Create Plan & Send Invites (\(emails.count + selectedFriendIds.count))")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(DS.Colors.plan)
        .controlSize(.large)
        .disabled((emails.isEmpty && selectedFriendIds.isEmpty) || isSubmitting)
        .accessibilityLabel("Create plan and send \(emails.count + selectedFriendIds.count) invites")
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            Image(systemName: planAlreadyExisted ? "person.2.fill" : "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(planAlreadyExisted ? DS.Colors.plan : DS.Colors.success)
            Text(planAlreadyExisted ? "You already have a plan!" : "Invites sent!")
                .font(DS.Typography.titleSecondary)
            Text(
                planAlreadyExisted
                    ? (serverInviteCount > 0
                        ? (serverInviteCount == 1
                            ? "1 new invite sent to your existing plan."
                            : "\(serverInviteCount) new invites sent to your existing plan.")
                        : "Your group for this event already exists.")
                    : (serverInviteCount == 1
                        ? "1 friend has been invited to your plan."
                        : "\(serverInviteCount) friends have been invited to your plan.")
            )
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

    // MARK: - Data Loading

    private func loadSuggestions() async {
        do {
            let fetched = try await GraphQLClient.shared.fetchParticipantSuggestions(limit: 20)
            // Prefetch all avatars concurrently — warms NSCache before ForEach renders
            let urls = fetched.compactMap { $0.avatarUrl.flatMap { URL(string: $0) } }
            await DiceBearAvatar.prefetch(avatarUrls: urls)
            suggestions = fetched
        } catch {
            // Silently fail — suggestions are optional enhancement
        }
        isLoadingSuggestions = false
    }

    // MARK: - Actions

    private func toggleSuggestion(_ suggestion: ParticipantSuggestion) {
        if selectedFriendIds.contains(suggestion.userId) {
            selectedFriendIds.remove(suggestion.userId)
        } else {
            selectedFriendIds.insert(suggestion.userId)
        }
    }

    private func createPlan() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let plan = try await GraphQLClient.shared.createPlan(
                slug: event.slug,
                emails: emails,
                friendIds: Array(selectedFriendIds),
                message: message.isEmpty ? nil : message
            )

            planAlreadyExisted = plan.alreadyExists == true
            serverInviteCount = plan.inviteCount
            onPlanCreated(plan)
            withAnimation(DS.Animation.bouncy) {
                showSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
