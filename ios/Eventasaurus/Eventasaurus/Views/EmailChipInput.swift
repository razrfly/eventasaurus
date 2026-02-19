import SwiftUI

struct EmailChipInput: View {
    @Binding var emails: [String]
    @State private var currentInput = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Chips for added emails
            if !emails.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(emails, id: \.self) { email in
                        emailChip(email)
                    }
                }
            }

            // Input field
            HStack {
                TextField("friend@example.com", text: $currentInput)
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
        HStack(spacing: 4) {
            Text(email)
                .font(.caption)
                .lineLimit(1)

            Button {
                emails.removeAll { $0 == email }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.purple.opacity(0.1))
        .clipShape(Capsule())
    }

    private func addCurrentEmail() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle comma-separated paste
        let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

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
