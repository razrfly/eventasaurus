import SwiftUI

struct PollCreateSheet: View {
    let eventId: String
    let onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var votingSystem = "binary"
    @State private var hasDeadline = false
    @State private var votingDeadline = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var isSubmitting = false
    @State private var error: String?

    private let votingSystems = [
        ("binary", "Yes / Maybe / No"),
        ("approval", "Approval (multi-select)"),
        ("ranked", "Ranked Choice"),
        ("star", "Star Rating (1-5)")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Poll Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Voting System") {
                    Picker("System", selection: $votingSystem) {
                        ForEach(votingSystems, id: \.0) { system in
                            Text(system.1).tag(system.0)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Deadline") {
                    Toggle("Set voting deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $votingDeadline, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(DS.Typography.caption)
                    }
                }
            }
            .navigationTitle("Create Poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await submit() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil

        do {
            try await GraphQLClient.shared.createPoll(
                eventId: eventId,
                title: title.trimmingCharacters(in: .whitespaces),
                votingSystem: votingSystem,
                description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
                votingDeadline: hasDeadline ? votingDeadline : nil
            )
            await onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isSubmitting = false
        }
    }
}
