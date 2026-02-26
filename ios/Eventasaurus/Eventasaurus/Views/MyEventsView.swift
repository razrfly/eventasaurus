import SwiftUI

struct MyEventsView: View {

    // MARK: - Filter Enums

    enum TimeFilter: String, CaseIterable {
        case upcoming, past, archived
    }

    enum RoleFilter: String, CaseIterable {
        case all = "All Events"
        case hosting = "Hosting"
        case going = "Going"
        case pending = "Pending"
    }

    // MARK: - State

    @Binding var upcomingCount: Int

    @State private var timeFilter: TimeFilter = .upcoming
    @State private var roleFilter: RoleFilter = .all
    @State private var viewMode: EventViewMode = EventViewMode.load(key: "myEventsViewMode", default: .card)
    @State private var events: [DashboardEvent] = []
    @State private var filterCounts: DashboardFilterCounts?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showCreateSheet = false
    @State private var showProfileSheet = false
    @State private var refreshID = UUID()

    // Cache per time filter to avoid re-fetching on tab switch
    @State private var cache: [TimeFilter: [DashboardEvent]] = [:]

    init(upcomingCount: Binding<Int> = .constant(0)) {
        self._upcomingCount = upcomingCount
    }

    // MARK: - Computed

    private var filteredEvents: [DashboardEvent] {
        let base = events
        switch roleFilter {
        case .all:
            return base
        case .hosting:
            return base.filter { $0.role == .hosting }
        case .going:
            return base.filter { $0.role == .going }
        case .pending:
            return base.filter { $0.role == .pending }
        }
    }

    private var groupedEvents: [(key: Date?, events: [DashboardEvent])] {
        let dict = Dictionary(grouping: filteredEvents) { event -> Date? in
            guard let startsAt = event.startsAt else { return nil }
            return Calendar.current.startOfDay(for: startsAt)
        }

        let sorted = dict.sorted { lhs, rhs in
            // nil dates go last
            guard let l = lhs.key else { return false }
            guard let r = rhs.key else { return true }
            return timeFilter == .upcoming ? l < r : l > r
        }

        return sorted.map { (key: $0.key, events: $0.value) }
    }

    private var isPast: Bool {
        timeFilter == .past || timeFilter == .archived
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timeFilterPicker
                contentArea
            }
            .navigationTitle("My Events")
            .toolbar { toolbarContent }
            .task(id: refreshID) { await loadEvents(for: timeFilter) }
            .refreshable { await loadEvents(for: timeFilter, forceRefresh: true) }
            .onChange(of: timeFilter) { _, newValue in
                if let cached = cache[newValue] {
                    events = cached
                } else {
                    Task { await loadEvents(for: newValue) }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                EventCreateView { _ in
                    cache = [:]
                    refreshID = UUID()
                }
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
            }
            .navigationDestination(for: DashboardEvent.self) { event in
                if event.canManage {
                    EventManageView(slug: event.slug) {
                        self.refreshID = UUID()
                    }
                } else {
                    EventDetailView(slug: event.slug)
                }
            }
        }
    }

    // MARK: - Time Filter Picker

    private var timeFilterPicker: some View {
        Picker("", selection: $timeFilter) {
            ForEach(TimeFilter.allCases, id: \.self) { filter in
                Text(timeFilterLabel(filter)).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.md)
    }

    private func timeFilterLabel(_ filter: TimeFilter) -> String {
        guard let counts = filterCounts else {
            return filter.rawValue.capitalized
        }
        let count: Int
        switch filter {
        case .upcoming: count = counts.upcoming
        case .past: count = counts.past
        case .archived: count = counts.archived
        }
        return "\(filter.rawValue.capitalized) (\(count))"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showProfileSheet = true
            } label: {
                Image(systemName: "person.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: DS.Spacing.md) {
                viewModeToggle
                roleFilterMenu
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var viewModeToggle: some View {
        ViewModeToggle(mode: $viewMode, persistKey: "myEventsViewMode")
    }

    private var roleFilterMenu: some View {
        Menu {
            ForEach(RoleFilter.allCases, id: \.self) { filter in
                Button {
                    roleFilter = filter
                } label: {
                    if roleFilter == filter {
                        Label(filter.rawValue, systemImage: "checkmark")
                    } else {
                        Text(filter.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: roleFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && events.isEmpty {
            ProgressView("Loading events...")
                .frame(maxHeight: .infinity)
        } else if let error, events.isEmpty {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Something went wrong",
                message: error.localizedDescription,
                actionTitle: "Try Again",
                action: { Task { await loadEvents(for: timeFilter, forceRefresh: true) } }
            )
        } else if filteredEvents.isEmpty {
            emptyState
        } else {
            eventList
        }
    }

    // MARK: - Event List

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var eventList: some View {
        ScrollView {
            if timeFilter == .archived {
                archiveBanner
            }

            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedEvents, id: \.key) { section in
                    Section {
                        Group {
                            switch viewMode {
                            case .compact, .card:
                                LazyVStack(spacing: viewMode == .compact ? DS.Spacing.xs : DS.Spacing.xl) {
                                    ForEach(section.events) { event in
                                        NavigationLink(value: event) {
                                            dashboardCard(for: event)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            case .grid:
                                LazyVGrid(columns: gridColumns, spacing: DS.Spacing.lg) {
                                    ForEach(section.events) { event in
                                        NavigationLink(value: event) {
                                            dashboardCard(for: event)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.bottom, DS.Spacing.lg)
                    } header: {
                        sectionHeader(for: section.key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardCard(for event: DashboardEvent) -> some View {
        switch viewMode {
        case .compact:
            EventCompactRow(event: event, isPast: isPast) {
                EventRoleBadge(role: event.role)
            }

        case .card:
            EventStandardCard(event: event, isPast: isPast) {
                // Cover: status badge
                HStack {
                    DashboardBadges.statusBadge(event.status)
                    Spacer()
                }
            } subtitleContent: {
                if let tagline = event.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(DS.Typography.bodyItalic)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let startsAt = event.startsAt {
                    Label {
                        Text(startsAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                }

                if let venue = event.venue {
                    Label(venue.name ?? "Unknown Venue", systemImage: "mappin")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if event.isVirtual {
                    Label("Online", systemImage: "video")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            } bottomRow: {
                HStack {
                    if let count = event.displayParticipantCount {
                        Label("\(count)", systemImage: "person.2")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    EventRoleBadge(role: event.role)
                }
            }

        case .grid:
            EventGridCard(event: event, isPast: isPast) {
                // Cover: status badge
                HStack {
                    DashboardBadges.statusBadge(event.status)
                    Spacer()
                }
            } subtitleContent: {
                if let startsAt = event.startsAt {
                    Text(startsAt, format: .dateTime.month(.abbreviated).day())
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionHeader(for date: Date?) -> some View {
        HStack {
            if let date {
                Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(.secondary)
            } else {
                Text("No Date Set")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.sm)
        .background(.bar)
    }

    private var archiveBanner: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "info.circle")
            Text("Deleted events are kept for 90 days.")
                .font(DS.Typography.caption)
        }
        .foregroundStyle(.secondary)
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Empty States

    @ViewBuilder
    private var emptyState: some View {
        switch (timeFilter, roleFilter) {
        case (.upcoming, .all):
            EmptyStateView(
                icon: "calendar.badge.plus",
                title: "No Upcoming Events",
                message: "Create an event or RSVP to one to see it here.",
                actionTitle: "Create Event",
                action: { showCreateSheet = true }
            )
        case (.upcoming, .hosting):
            EmptyStateView(
                icon: "star.circle",
                title: "Not Hosting Any Events",
                message: "Create an event to start hosting.",
                actionTitle: "Create Event",
                action: { showCreateSheet = true }
            )
        case (.upcoming, .going):
            EmptyStateView(
                icon: "checkmark.circle",
                title: "No Events You're Attending",
                message: "RSVP to events to see them here."
            )
        case (.upcoming, .pending):
            EmptyStateView(
                icon: "clock",
                title: "No Pending Invitations",
                message: "You're all caught up!"
            )
        case (.past, .all):
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No Past Events",
                message: "Events you've attended will appear here."
            )
        case (.past, .hosting):
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No Past Hosted Events",
                message: "Events you've hosted will appear here after they end."
            )
        case (.past, _):
            EmptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No Past Events",
                message: "Nothing here yet."
            )
        case (.archived, _):
            EmptyStateView(
                icon: "archivebox",
                title: "No Archived Events",
                message: "Deleted events will appear here for 90 days."
            )
        }
    }

    // MARK: - Data Loading

    private func loadEvents(for filter: TimeFilter, forceRefresh: Bool = false) async {
        if !forceRefresh, cache[filter] != nil { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let gqlTimeFilter: DashboardTimeFilter
            switch filter {
            case .upcoming: gqlTimeFilter = .upcoming
            case .past: gqlTimeFilter = .past
            case .archived: gqlTimeFilter = .archived
            }

            let result = try await GraphQLClient.shared.fetchDashboardEvents(
                timeFilter: gqlTimeFilter
            )

            events = result.events
            filterCounts = result.filterCounts
            upcomingCount = result.filterCounts.upcoming
            cache[filter] = result.events
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }
}
