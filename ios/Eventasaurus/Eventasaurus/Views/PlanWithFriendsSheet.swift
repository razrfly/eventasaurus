import SwiftUI

struct PlanWithFriendsSheet: View {
    let event: Event
    var onPlanCreated: (GQLPlan) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var emails: [String] = []
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

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
        .presentationDetents([.medium, .large])
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                // Event header
                HStack(spacing: DS.Spacing.lg) {
                    CachedImage(
                        url: event.coverImageUrl.flatMap { URL(string: $0) },
                        height: DS.ImageSize.thumbnail,
                        cornerRadius: DS.Radius.md,
                        placeholderIcon: "calendar"
                    )
                    .frame(width: DS.ImageSize.thumbnail)

                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(event.title)
                            .font(DS.Typography.bodyMedium)
                            .lineLimit(2)
                        if let date = event.startsAt {
                            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Email input
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Invite friends by email")
                        .font(DS.Typography.bodyMedium)
                    Text("They'll receive an email invitation to join your plan.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    EmailChipInput(emails: $emails)
                }

                Divider()

                // Message
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Message (optional)")
                        .font(DS.Typography.bodyMedium)
                    TextField("Let's go together!", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.error)
                }

                // Submit button
                Button {
                    Task { await createPlan() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create Plan & Send Invites (\(emails.count))")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Colors.plan)
                .controlSize(.large)
                .disabled(emails.isEmpty || isSubmitting)
                .accessibilityLabel("Create plan and send \(emails.count) invites")
            }
            .padding(DS.Spacing.xl)
        }
    }

    private var successView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DS.Colors.success)
            Text("Invites sent!")
                .font(DS.Typography.titleSecondary)
            Text("\(emails.count) friends have been invited to your plan.")
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

    private func createPlan() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let plan = try await GraphQLClient.shared.createPlan(
                slug: event.slug,
                emails: emails,
                message: message.isEmpty ? nil : message
            )

            onPlanCreated(plan)
            withAnimation(DS.Animation.bouncy) {
                showSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
