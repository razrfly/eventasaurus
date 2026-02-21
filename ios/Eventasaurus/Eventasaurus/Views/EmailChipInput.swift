import SwiftUI

struct EmailChipInput: View {
    @Binding var emails: [String]
    @State private var currentInput = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Chips for added emails
            if !emails.isEmpty {
                FlowLayout(spacing: DS.Spacing.sm) {
                    ForEach(emails, id: \.self) { email in
                        emailChip(email)
                    }
                }
            }

            // Input field
            HStack {
                TextField("Enter email address", text: $currentInput)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit { addCurrentEmail() }

                Button("Add") {
                    addCurrentEmail()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isValidEmail(currentInput))
            }
        }
    }

    private func emailChip(_ email: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(email)
                .font(DS.Typography.caption)
                .lineLimit(1)

            Button {
                emails.removeAll { $0 == email }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Typography.micro)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Colors.plan.opacity(DS.Opacity.tintedBackground))
        .clipShape(Capsule())
    }

    private func addCurrentEmail() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle comma, semicolon, or newline-separated paste
        let parts = trimmed
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: "\r", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        for part in parts {
            if isValidEmail(part) && !emails.contains(part) {
                emails.append(part)
            }
        }

        currentInput = ""
        isFocused = true
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Simple validation: contains @ with text on both sides
        let parts = trimmed.split(separator: "@")
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }
}
