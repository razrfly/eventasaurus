import SwiftUI

struct MyEventsView: View {
    enum Tab: String, CaseIterable {
        case created = "Created"
        case attending = "Attending"
    }

    enum NavigationTarget: Hashable {
        case created(UserEvent)
        case attending(UserEvent)
    }

    @State private var selectedTab: Tab = .created
    @State private var createdEvents: [UserEvent] = []
    @State private var attendingEvents: [UserEvent] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showCreateSheet = false
    @State private var currentLoadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.md)

                // Tab content
                Group {
                    switch selectedTab {
                    case .created:
                        createdContent
                    case .attending:
                        attendingContent
                    }
                }
            }
            .navigationTitle("My Events")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await loadData() }
            .refreshable { await loadData() }
            .onChange(of: selectedTab) { _, _ in
                currentLoadTask?.cancel()
                currentLoadTask = Task { await loadData() }
            }
            .sheet(isPresented: $showCreateSheet) {
                EventCreateView { newEvent in
                    createdEvents.insert(newEvent, at: 0)
                    selectedTab = .created
                }
            }
            .navigationDestination(for: NavigationTarget.self) { target in
                switch target {
                case .created(let event):
                    EventManageView(event: event) {
                        Task { await loadCreatedEvents() }
                    }
                case .attending(let event):
                    EventDetailView(slug: event.slug)
                }
            }
        }
    }

    // MARK: - Created Tab

    @ViewBuilder
    private var createdContent: some View {
        if isLoading && createdEvents.isEmpty {
            ProgressView("Loading your events...")
                .frame(maxHeight: .infinity)
        } else if let error, createdEvents.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Something went wrong",
                message: error.localizedDescription,
                actionTitle: "Try Again",
                action: { Task { await loadCreatedEvents() } }
            )
        } else if createdEvents.isEmpty {
            EmptyStateView(
                icon: "plus.circle",
                title: "No Events Created",
                message: "Create your first event to get started.",
                actionTitle: "Create Event",
                action: { showCreateSheet = true }
            )
        } else {
            createdEventList
        }
    }

    private var createdEventList: some View {
        ScrollView {
            LazyVStack(spacing: DS.Spacing.xl) {
                ForEach(createdEvents) { event in
                    NavigationLink(value: NavigationTarget.created(event)) {
                        UserEventCardView(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.Spacing.xl)
        }
    }

    // MARK: - Attending Tab

    @ViewBuilder
    private var attendingContent: some View {
        if isLoading && attendingEvents.isEmpty {
            ProgressView("Loading your events...")
                .frame(maxHeight: .infinity)
        } else if let error, attendingEvents.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Something went wrong",
                message: error.localizedDescription,
                actionTitle: "Try Again",
                action: { Task { await loadAttendingEvents() } }
            )
        } else if attendingEvents.isEmpty {
            EmptyStateView(
                icon: "calendar",
                title: "No Events Yet",
                message: "You haven't joined any events yet."
            )
        } else {
            attendingEventList
        }
    }

    private var attendingEventList: some View {
        ScrollView {
            LazyVStack(spacing: DS.Spacing.xl) {
                ForEach(attendingEvents) { event in
                    NavigationLink(value: NavigationTarget.attending(event)) {
                        UserEventCardView(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.Spacing.xl)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        switch selectedTab {
        case .created:
            await loadCreatedEvents()
        case .attending:
            await loadAttendingEvents()
        }
    }

    private func loadCreatedEvents() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            createdEvents = try await GraphQLClient.shared.fetchMyEvents()
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }

    private func loadAttendingEvents() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            attendingEvents = try await GraphQLClient.shared.fetchAttendingEvents()
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }
}
