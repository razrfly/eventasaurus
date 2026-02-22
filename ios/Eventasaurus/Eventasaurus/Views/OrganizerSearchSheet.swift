import SwiftUI

/// Search sheet for finding and adding co-organizers.
/// Searches existing users by name, username, or email.
struct OrganizerSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    let slug: String
    var onAdd: (() async -> Void)?

    var body: some View {
        NavigationStack {
            List {
                if searchText.count < 2 {
                    Section {
                        Text("Type at least 2 characters to search")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                } else if isSearching {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Searching...")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if searchResults.isEmpty {
                    Section {
                        Text("No users found")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(searchResults) { user in
                            Button {
                                guard let email = user.email else { return }
                                Task { await addOrganizer(email: email) }
                            } label: {
                                userRow(user)
                            }
                            .buttonStyle(.plain)
                            .disabled(isAdding || user.email == nil)
                        }
                    } header: {
                        Text("Results")
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search by name, username, or email...")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                guard newValue.trimmingCharacters(in: .whitespaces).count >= 2 else {
                    searchResults = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await performSearch(newValue)
                }
            }
            .onDisappear {
                searchTask?.cancel()
                searchTask = nil
            }
            .navigationTitle("Add Co-organizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isAdding {
                    ProgressView("Adding...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
            }
        }
    }

    // MARK: - Row

    private func userRow(_ user: UserSearchResult) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DiceBearAvatar(
                url: user.avatarUrl.flatMap { URL(string: $0) },
                size: 32
            )

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(user.name)
                    .font(DS.Typography.bodyMedium)

                if let email = user.email {
                    Text(email)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if let username = user.username {
                    Text("@\(username)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Actions

    private func performSearch(_ query: String) async {
        isSearching = true
        error = nil
        do {
            let results = try await GraphQLClient.shared.searchUsersForOrganizers(
                query: query,
                slug: slug
            )
            // Only update if this task wasn't cancelled while the request was in-flight
            guard !Task.isCancelled else { return }
            searchResults = results
        } catch is CancellationError {
            return // Don't update UI state for cancelled requests
        } catch let urlError as URLError where urlError.code == .cancelled {
            return // URLSession cancellation — don't update UI state
        } catch {
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("[OrganizerSearchSheet] Search failed: \(error)")
            #endif
            self.error = error.localizedDescription
        }
        isSearching = false
    }

    private func addOrganizer(email: String) async {
        isAdding = true
        error = nil
        do {
            try await GraphQLClient.shared.addOrganizer(slug: slug, email: email)
            await onAdd?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isAdding = false
        }
    }
}
