import SwiftUI

struct DiscoverView: View {
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var locationManager = LocationManager()
    @State private var lastLat: Double?
    @State private var lastLng: Double?

    // Category filtering
    @State private var categories: [Category] = []
    @State private var selectedCategories: Set<Int> = []

    // City selection
    @State private var selectedCity: City?
    @State private var resolvedCity: City?
    @State private var locationResolved = false
    @State private var showCityPicker = false

    // Search
    @State private var searchText = ""

    // Date filtering
    @State private var selectedDateRange: String?

    // Sort options
    @State private var sortBy: String = "starts_at"
    @State private var sortOrder: String = "asc"

    // Pagination
    @State private var currentPage = 1
    @State private var totalCount = 0
    @State private var isLoadingMore = false
    @State private var loadGeneration = 0

    // Date range counts from API
    @State private var dateRangeCounts: [String: Int] = [:]
    @State private var allEventsCount: Int = 0

    // View mode (compact/card/grid)
    @State private var viewMode: EventViewMode = EventViewMode.load(key: "discoverViewMode", default: .compact)

    // Filters sheet
    @State private var showFilters = false
    @State private var isDateControlVisible = true
    @State private var radiusKm: Double = {
        let saved = UserDefaults.standard.double(forKey: "discoverRadiusKm")
        return saved > 0 ? saved : 50
    }()

    // Language
    @State private var language: String = UserDefaults.standard.string(forKey: "discoverLanguage") ?? "en"

    // Number of rows to interleave category chips across
    private let categoryRowCount = 2

    private enum SegmentedDateRange: String, CaseIterable {
        case all, today, thisWeek

        var label: String {
            switch self {
            case .all: "All"
            case .today: "Today"
            case .thisWeek: "This Week"
            }
        }

        var apiValue: String? {
            switch self {
            case .all: nil
            case .today: "today"
            case .thisWeek: "next_7_days"
            }
        }
    }

    private static let overflowDateRanges: [(label: String, value: String)] = [
        ("Tomorrow", "tomorrow"),
        ("This Weekend", "this_weekend"),
        ("Next 30 Days", "next_30_days"),
        ("This Month", "this_month"),
        ("Next Month", "next_month"),
    ]

    private static let cityKey = "selectedCityId"
    private static let cityNameKey = "selectedCityName"
    private static let citySlugKey = "selectedCitySlug"
    private static let cityCountryKey = "selectedCityCountry"
    private static let cityCountryCodeKey = "selectedCityCountryCode"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date filter — hides while scrolling on iOS 18+
                if isDateControlVisible {
                    filterChips
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Event content
                Group {
                    if isLoading && events.isEmpty {
                        Spacer()
                        ProgressView("Finding events nearby...")
                            .transition(.opacity)
                        Spacer()
                    } else if let error, events.isEmpty {
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "Something went wrong",
                            message: error.localizedDescription,
                            actionTitle: "Try Again",
                            action: { Task { await requestLocationAndLoad() } }
                        )
                    } else if events.isEmpty && !isLoading {
                        EmptyStateView(
                            icon: "calendar.badge.exclamationmark",
                            title: "No Events Found",
                            message: "No events match your filters. Try adjusting your search criteria.",
                            actionTitle: hasActiveFilters ? "Clear Filters" : nil,
                            action: hasActiveFilters ? {
                                clearFilters()
                                Task { await loadEvents() }
                            } : nil
                        )
                    } else {
                        eventList
                            .transition(.opacity)
                    }
                }
                .animation(DS.Animation.standard, value: isLoading)
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCityPicker = true
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: selectedCity != nil ? "building.2" : "location.fill")
                            Text(selectedCity?.name ?? resolvedCity?.name ?? "Nearby")
                                .lineLimit(1)
                        }
                        .font(DS.Typography.body)
                    }
                    .accessibilityLabel("City: \(selectedCity?.name ?? resolvedCity?.name ?? "Nearby")")
                    .accessibilityHint("Opens city picker")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    ViewModeToggle(mode: $viewMode, persistKey: "discoverViewMode")

                    // Filters button
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(DS.Typography.body)
                            .overlay(alignment: .topTrailing) {
                                if hasAdvancedFilters {
                                    Circle()
                                        .fill(DS.Colors.error)
                                        .frame(width: DS.ImageSize.indicatorDot, height: DS.ImageSize.indicatorDot)
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    .accessibilityLabel(hasAdvancedFilters ? "Filters, active" : "Filters")
                    .accessibilityHint("Opens filter options")
                }
            }
            .searchable(text: $searchText, prompt: "Search events...")
            .searchMinimized()
            .onSubmit(of: .search) {
                Task { await loadEvents() }
            }
            .onChange(of: searchText) {
                if searchText.isEmpty {
                    Task { await loadEvents() }
                }
            }
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(
                    selectedCity: selectedCity,
                    resolvedCity: resolvedCity,
                    locationDenied: locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted,
                    locationResolved: locationResolved
                ) { city in
                    selectedCity = city
                    persistCitySelection(city)
                    Task { await loadEvents() }
                }
            }
            .sheet(isPresented: $showFilters) {
                FiltersSheet(
                    radiusKm: $radiusKm,
                    sortBy: $sortBy,
                    sortOrder: $sortOrder,
                    selectedCategories: $selectedCategories,
                    language: $language,
                    categoryItems: categories.compactMap { cat in
                        guard let catId = cat.numericId else { return nil }
                        return FilterCategoryItem(id: catId, name: cat.name, icon: cat.icon, color: cat.resolvedColor)
                    }
                ) {
                    UserDefaults.standard.set(radiusKm, forKey: "discoverRadiusKm")
                    UserDefaults.standard.set(language, forKey: "discoverLanguage")
                    Task { await loadEvents() }
                }
            }
            .task {
                restoreCitySelection()
                await loadCategories()
                await requestLocationAndLoad()
            }
            .refreshable { await requestLocationAndLoad() }
            .navigationDestination(for: EventDestination.self) { destination in
                switch destination {
                case .event(let slug):
                    EventDetailView(slug: slug)
                case .movieGroup(let slug, let cityId):
                    MovieDetailView(slug: slug, cityId: cityId)
                case .eventGroup(let slug, let cityId):
                    SourceDetailView(slug: slug, cityId: cityId)
                case .containerGroup(let slug):
                    ContainerDetailView(slug: slug)
                case .venue(let slug):
                    VenueDetailView(slug: slug)
                }
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Sort by Date")
                .font(DS.Typography.captionBold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Spacing.xl)

            HStack(spacing: DS.Spacing.md) {
                Picker("Date range", selection: Binding<SegmentedDateRange>(
                    get: { activeSegment ?? .all },
                    set: { newValue in
                        withAnimation(DS.Animation.fast) {
                            selectedDateRange = newValue.apiValue
                        }
                        Task { await loadEvents() }
                    }
                )) {
                    ForEach(SegmentedDateRange.allCases, id: \.self) { segment in
                        segmentLabel(segment)
                            .tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .opacity(isOverflowDateActive ? 0.5 : 1)

                Menu {
                    ForEach(Self.overflowDateRanges, id: \.value) { range in
                        Button {
                            withAnimation(DS.Animation.fast) {
                                selectedDateRange = range.value
                            }
                            Task { await loadEvents() }
                        } label: {
                            Label {
                                overflowMenuLabel(range.label, value: range.value)
                            } icon: {
                                if selectedDateRange == range.value {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: isOverflowDateActive ? "calendar.circle.fill" : "calendar.circle")
                        .font(.title2)
                        .foregroundStyle(isOverflowDateActive ? .primary : .secondary)
                }
                .accessibilityLabel("More date ranges")
                .accessibilityValue(overflowAccessibilityValue)
            }
            .padding(.horizontal, DS.Spacing.xl)
        }
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: - Category Browse Section (scrollable)

    @ViewBuilder
    private var categoryBrowseSection: some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("Browse by Category")
                    .font(DS.Typography.captionBold)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        ForEach(0..<categoryRowCount, id: \.self) { row in
                            categoryChipRow(from: row)
                        }
                    }
                }
            }
            .padding(.bottom, DS.Spacing.md)
        }
    }

    @ViewBuilder
    private func categoryChipRow(from startIndex: Int) -> some View {
        let rowCategories = stride(from: startIndex, to: categories.count, by: categoryRowCount).compactMap { $0 < categories.count ? categories[$0] : nil }
        HStack(spacing: DS.Spacing.md) {
            ForEach(rowCategories) { cat in
                if let catId = cat.numericId {
                    CategoryBrowseChip(
                        category: cat,
                        isSelected: selectedCategories.contains(catId)
                    ) {
                        toggleCategory(catId)
                    }
                }
            }
        }
    }

    /// Get the count for a given date range value
    private func countForDateRange(_ value: String?) -> Int? {
        if let value {
            return dateRangeCounts[value]
        } else {
            return allEventsCount > 0 ? allEventsCount : (totalCount > 0 ? totalCount : nil)
        }
    }

    private func segmentLabel(_ segment: SegmentedDateRange) -> Text {
        if let count = countForDateRange(segment.apiValue) {
            Text("\(segment.label) (\(count))")
        } else {
            Text(segment.label)
        }
    }

    @ViewBuilder
    private func overflowMenuLabel(_ label: String, value: String) -> some View {
        if let count = countForDateRange(value) {
            Text("\(label) (\(count))")
        } else {
            Text(label)
        }
    }

    private var overflowAccessibilityValue: String {
        if let active = Self.overflowDateRanges.first(where: { $0.value == selectedDateRange }) {
            return active.label
        }
        return "None selected"
    }

    // MARK: - Event List

    private var hasMorePages: Bool {
        events.count < totalCount
    }

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var eventList: some View {
        ScrollView {
            VStack(spacing: 0) {
                categoryBrowseSection

                // Pagination info
                if totalCount > 0 {
                    HStack {
                        Text(paginationText)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.bottom, DS.Spacing.md)
                }

                switch viewMode {
                case .compact, .card:
                    LazyVStack(spacing: viewMode == .compact ? DS.Spacing.xs : DS.Spacing.xl) {
                        eventItems
                    }
                case .grid:
                    LazyVGrid(columns: gridColumns, spacing: DS.Spacing.lg) {
                        eventItems
                    }
                }

                if isLoadingMore {
                    ProgressView()
                        .padding(DS.Spacing.xl)
                }
            }
            .padding(DS.Spacing.xl)
        }
        .modifier(ScrollAwareFilterModifier(isDateControlVisible: $isDateControlVisible))
    }

    @ViewBuilder
    private var eventItems: some View {
        ForEach(events) { event in
            NavigationLink(value: event.destination(cityId: selectedCity?.id)) {
                discoverCard(for: event)
            }
            .buttonStyle(.plain)
            .onAppear {
                if event.id == events.last?.id, hasMorePages, !isLoadingMore {
                    Task { await loadMoreEvents() }
                }
            }
        }
    }

    @ViewBuilder
    private func discoverCard(for event: Event) -> some View {
        switch viewMode {
        case .compact:
            EventCompactRow(event: event) {
                // Trailing: group badge or time badge
                if event.isGroup {
                    DiscoverBadges.groupBadge(for: event, compact: true)
                } else if let badge = event.timeBadgeText(compact: true) {
                    DiscoverBadges.timeBadge(badge)
                }
            }

        case .card:
            EventStandardCard(event: event) {
                // Cover badges
                HStack {
                    if let category = event.primaryCategory, !event.isGroup {
                        DiscoverBadges.categoryBadge(category)
                    }
                    Spacer()
                    if event.isGroup {
                        DiscoverBadges.groupBadge(for: event)
                    } else if let badge = event.timeBadgeText() {
                        DiscoverBadges.timeBadge(badge)
                    }
                }
            } subtitleContent: {
                // Subtitle for groups, date+venue for regular events
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                } else {
                    if let date = event.startsAt {
                        Text(date, style: .date)
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                    if let venue = event.venue {
                        Label(venue.displayName, systemImage: "mappin")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

        case .grid:
            EventGridCard(event: event) {
                // Cover badges
                HStack {
                    if let category = event.primaryCategory, !event.isGroup {
                        DiscoverBadges.categoryBadge(category)
                    }
                    Spacer()
                    if event.isGroup {
                        DiscoverBadges.groupBadge(for: event, compact: true)
                    } else if let badge = event.timeBadgeText(compact: true) {
                        DiscoverBadges.timeBadge(badge)
                    }
                }
            } subtitleContent: {
                if let date = event.startsAt, !event.isGroup {
                    Text(date, style: .date)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                } else if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var paginationText: String {
        let showing = min(events.count, totalCount)
        return "Showing \(showing) of \(totalCount) events"
    }

    // MARK: - Data Loading

    private func loadCategories() async {
        do {
            categories = try await APIClient.shared.fetchCategories()
        } catch {
            // Non-critical; continue without categories
        }
    }

    private func requestLocationAndLoad() async {
        if selectedCity != nil {
            await loadEvents()
            return
        }

        if isLoading && events.isEmpty {
            // Already loading initial
        } else {
            isLoading = true
        }
        error = nil

        let loc = locationManager.location != nil
            ? locationManager.location
            : await locationManager.getLocation(timeout: 10)

        if let loc {
            lastLat = loc.coordinate.latitude
            lastLng = loc.coordinate.longitude
            await loadEvents()
            locationResolved = false
            resolvedCity = try? await APIClient.shared.resolveCity(
                lat: loc.coordinate.latitude, lng: loc.coordinate.longitude
            )
            locationResolved = true
        } else {
            isLoading = false
            locationResolved = true
            error = LocationError.unavailable
        }
    }

    private func loadEvents() async {
        if selectedCity == nil {
            guard lastLat != nil, lastLng != nil else {
                await requestLocationAndLoad()
                return
            }
        }

        currentPage = 1
        loadGeneration += 1
        isLoading = true
        error = nil

        do {
            let response = try await APIClient.shared.fetchNearbyEvents(
                lat: selectedCity == nil ? lastLat : nil,
                lng: selectedCity == nil ? lastLng : nil,
                radius: radiusKm * 1000,
                cityId: selectedCity?.id,
                categoryIds: Array(selectedCategories),
                search: searchText.isEmpty ? nil : searchText,
                dateRange: selectedDateRange,
                sortBy: sortBy == "starts_at" ? nil : sortBy,
                sortOrder: sortOrder == "asc" ? nil : sortOrder,
                page: 1,
                language: language
            )
            events = response.events
            assert(response.meta.resolvedTotal != nil, "Backend meta missing both total_count and total")
            totalCount = response.meta.resolvedTotal ?? response.events.count

            if let counts = response.meta.dateRangeCounts {
                dateRangeCounts = counts
            }
            if let allCount = response.meta.allEventsCount {
                allEventsCount = allCount
            }
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            self.error = error
            dateRangeCounts = [:]
            allEventsCount = 0
        }

        isLoading = false
    }

    private func loadMoreEvents() async {
        let nextPage = currentPage + 1
        let generation = loadGeneration
        isLoadingMore = true

        do {
            let response = try await APIClient.shared.fetchNearbyEvents(
                lat: selectedCity == nil ? lastLat : nil,
                lng: selectedCity == nil ? lastLng : nil,
                radius: radiusKm * 1000,
                cityId: selectedCity?.id,
                categoryIds: Array(selectedCategories),
                search: searchText.isEmpty ? nil : searchText,
                dateRange: selectedDateRange,
                sortBy: sortBy == "starts_at" ? nil : sortBy,
                sortOrder: sortOrder == "asc" ? nil : sortOrder,
                page: nextPage,
                language: language
            )
            guard generation == loadGeneration else { isLoadingMore = false; return }
            let existingIds = Set(events.map(\.id))
            let newEvents = response.events.filter { !existingIds.contains($0.id) }
            events.append(contentsOf: newEvents)
            currentPage = nextPage
            totalCount = response.meta.resolvedTotal ?? totalCount
        } catch {
            // Silently fail load-more; user can scroll again to retry
        }

        isLoadingMore = false
    }

    // MARK: - Filter Helpers

    private var activeSegment: SegmentedDateRange? {
        SegmentedDateRange.allCases.first { $0.apiValue == selectedDateRange }
    }

    private var isOverflowDateActive: Bool {
        selectedDateRange != nil && activeSegment == nil
    }

    private var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || selectedDateRange != nil || !searchText.isEmpty
    }

    private var hasAdvancedFilters: Bool {
        radiusKm != 50 || sortBy != "starts_at" || sortOrder != "asc" || language != "en" || !selectedCategories.isEmpty
    }

    private func clearFilters() {
        selectedCategories.removeAll()
        selectedDateRange = nil
        searchText = ""
        sortBy = "starts_at"
        sortOrder = "asc"
        radiusKm = 50
        language = "en"
        UserDefaults.standard.set(radiusKm, forKey: "discoverRadiusKm")
        UserDefaults.standard.set(language, forKey: "discoverLanguage")
    }

    private func toggleCategory(_ id: Int) {
        withAnimation(DS.Animation.fast) {
            if selectedCategories.contains(id) {
                selectedCategories.remove(id)
            } else {
                selectedCategories.insert(id)
            }
        }
        Task { await loadEvents() }
    }

    // MARK: - City Persistence

    private func persistCitySelection(_ city: City?) {
        if let city {
            UserDefaults.standard.set(city.id, forKey: Self.cityKey)
            UserDefaults.standard.set(city.name, forKey: Self.cityNameKey)
            UserDefaults.standard.set(city.slug, forKey: Self.citySlugKey)
            UserDefaults.standard.set(city.country, forKey: Self.cityCountryKey)
            UserDefaults.standard.set(city.countryCode, forKey: Self.cityCountryCodeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.cityKey)
            UserDefaults.standard.removeObject(forKey: Self.cityNameKey)
            UserDefaults.standard.removeObject(forKey: Self.citySlugKey)
            UserDefaults.standard.removeObject(forKey: Self.cityCountryKey)
            UserDefaults.standard.removeObject(forKey: Self.cityCountryCodeKey)
        }
    }

    private func restoreCitySelection() {
        let cityId = UserDefaults.standard.integer(forKey: Self.cityKey)
        if cityId > 0, let name = UserDefaults.standard.string(forKey: Self.cityNameKey) {
            let slug = UserDefaults.standard.string(forKey: Self.citySlugKey) ?? ""
            let country = UserDefaults.standard.string(forKey: Self.cityCountryKey)
            let countryCode = UserDefaults.standard.string(forKey: Self.cityCountryCodeKey)
            selectedCity = City(id: cityId, name: name, slug: slug, latitude: nil, longitude: nil, timezone: nil, country: country, countryCode: countryCode, eventCount: nil)
        }
    }
}

// MARK: - Scroll-Aware Filter Modifier

private struct ScrollAwareFilterModifier: ViewModifier {
    @Binding var isDateControlVisible: Bool
    @State private var hideTask: Task<Void, Never>?

    /// Minimum scroll duration before hiding the date control, avoids rapid toggles from short taps/scrolls
    private let debounceInterval: Duration = .milliseconds(150)

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .tracking:
                        hideTask?.cancel()
                        hideTask = Task {
                            try? await Task.sleep(for: debounceInterval)
                            guard !Task.isCancelled else { return }
                            withAnimation(DS.Animation.fast) {
                                isDateControlVisible = false
                            }
                        }
                    case .idle:
                        hideTask?.cancel()
                        hideTask = nil
                        withAnimation(DS.Animation.fast) {
                            isDateControlVisible = true
                        }
                    default:
                        break
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Search Minimize (iOS 26+)

fileprivate extension View {
    /// Minimizes the search toolbar when available. searchToolbarBehavior(.minimize) requires iOS 26+.
    @ViewBuilder
    func searchMinimized() -> some View {
        if #available(iOS 26.0, *) {
            self.searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }
}

// MARK: - Chip Views

struct CategoryBrowseChip: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void

    private var accentColor: Color { category.resolvedColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                // Icon square
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(category.icon ?? "📅")
                            .font(.system(size: 16))
                    }

                Text(category.name)
                    .font(DS.Typography.captionMedium)
                    .foregroundStyle(isSelected ? accentColor : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(isSelected ? accentColor.opacity(0.12) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(
                        isSelected ? accentColor : Color(.systemGray4),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum LocationError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Unable to determine your location. Please check location permissions in Settings."
        }
    }
}
