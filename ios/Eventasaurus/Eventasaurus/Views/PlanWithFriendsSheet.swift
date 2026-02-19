import SwiftUI

struct PlanWithFriendsSheet: View {
    let event: Event
    var onPlanCreated: (PlanInfo) -> Void = { _ in }

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
            VStack(alignment: .leading, spacing: 20) {
                // Event header
                HStack(spacing: 12) {
                    CachedImage(
                        url: event.coverImageUrl.flatMap { URL(string: $0) },
                        height: 60,
                        cornerRadius: 8,
                        placeholderIcon: "calendar"
                    )
                    .frame(width: 60)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if let date = event.startsAt {
                            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Email input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Invite friends by email")
                        .font(.subheadline.weight(.medium))
                    Text("They'll receive an email invitation to join your plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    EmailChipInput(emails: $emails)
                }

                Divider()

                // Message
                VStack(alignment: .leading, spacing: 6) {
                    Text("Message (optional)")
                        .font(.subheadline.weight(.medium))
                    TextField("Let's go together!", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                .tint(.purple)
                .controlSize(.large)
                .disabled(emails.isEmpty || isSubmitting)
            }
            .padding()
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Invites sent!")
                .font(.title3.weight(.semibold))
            Text("\(emails.count) friends have been invited to your plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }

    private func createPlan() async {
        isSubmitting = true
        errorMessage = nil

        do {
            let response = try await APIClient.shared.createPlanWithFriends(
                eventSlug: event.slug,
                emails: emails,
                message: message.isEmpty ? nil : message
            )

            if let plan = response.plan {
                onPlanCreated(plan)
                showSuccess = true
            } else {
                errorMessage = "Could not create plan. Please try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}
