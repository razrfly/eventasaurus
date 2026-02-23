#if DEBUG
import SwiftUI

struct DevUserPickerView: View {
    @Environment(\.dismiss) private var dismiss
    var devAuth = DevAuthService.shared

    var body: some View {
        NavigationStack {
            Group {
                if devAuth.isLoadingUsers {
                    ProgressView("Loading users...")
                } else if let users = devAuth.users {
                    userList(users)
                } else {
                    ContentUnavailableView(
                        "No Users",
                        systemImage: "person.slash",
                        description: Text("Could not load dev users. Is the server running?")
                    )
                }
            }
            .navigationTitle("Dev Quick Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await devAuth.fetchUsers() }
    }

    private func userList(_ users: DevQuickLoginUsers) -> some View {
        List {
            if !users.personal.isEmpty {
                Section("Personal") {
                    ForEach(users.personal) { user in
                        userRow(user)
                    }
                }
            }

            if !users.organizers.isEmpty {
                Section("Event Organizers") {
                    ForEach(users.organizers) { user in
                        userRow(user)
                    }
                }
            }

            if !users.participants.isEmpty {
                Section("Event Participants") {
                    ForEach(users.participants) { user in
                        userRow(user)
                    }
                }
            }
        }
    }

    private func userRow(_ user: DevUser) -> some View {
        Button {
            devAuth.selectUser(id: user.id, name: user.name ?? user.email)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(user.label)
                    .font(.body)
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
