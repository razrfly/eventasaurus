import SwiftUI

enum ViewMode: String {
    case list, grid
}

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

    // View mode (grid/list)
    @State private var viewMode: ViewMode = {
        let saved = UserDefaults.standard.string(forKey: "discoverViewMode")
        return ViewMode(rawValue: saved ?? "") ?? .list
    }()

    // Filters sheet
    @State private var showFilters = false
    @State private var radiusKm: Double = {
        let saved = UserDefaults.standard.double(forKey: "discoverRadiusKm")
        return saved > 0 ? saved : 50
    }()

    // Language
    @State private var language: String = UserDefaults.standard.string(forKey: "discoverLanguage") ?? "en"

    private static let dateRanges: [(label: String, value: String?)] = [
        ("All Events", nil),
        ("Today", "today"),
        ("Tomorrow", "tomorrow"),
        ("This Weekend", "this_weekend"),
        ("Next 7 Days", "next_7_days"),
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
                // Filter chips — always visible, outside the scrollable event list
                filterChips

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
                    // Grid/List toggle
                    Button {
                        viewMode = viewMode == .list ? .grid : .list
                        UserDefaults.standard.set(viewMode.rawValue, forKey: "discoverViewMode")
                    } label: {
                        Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                            .font(DS.Typography.body)
                    }
                    .accessibilityLabel(viewMode == .list ? "Switch to grid view" : "Switch to list view")

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
        VStack(spacing: DS.Spacing.md) {
            // Category chips
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.md) {
                        ForEach(categories) { cat in
                            if let catId = cat.numericId {
                                CategoryChip(
                                    category: cat,
                                    isSelected: selectedCategories.contains(catId)
                                ) {
                                    toggleCategory(catId)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                }
            }

            // Date range chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.md) {
                    ForEach(Self.dateRanges, id: \.label) { range in
                        DateChip(
                            label: range.label,
                            count: countForDateRange(range.value),
                            isSelected: selectedDateRange == range.value
                        ) {
                            withAnimation(DS.Animation.fast) {
                                selectedDateRange = range.value
                            }
                            Task { await loadEvents() }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
        }
        .padding(.vertical, DS.Spacing.md)
    }

    /// Get the count for a given date range value
    private func countForDateRange(_ value: String?) -> Int? {
        if let value {
            return dateRangeCounts[value]
        } else {
            return allEventsCount > 0 ? allEventsCount : (totalCount > 0 ? totalCount : nil)
        }
    }

    // MARK: - Event List

    private var hasMorePages: Bool {
        events.count < totalCount
    }

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var eventList: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                case .list:
                    LazyVStack(spacing: DS.Spacing.xl) {
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
    }

    @ViewBuilder
    private var eventItems: some View {
        ForEach(events) { event in
            NavigationLink(value: event.destination(cityId: selectedCity?.id)) {
                switch viewMode {
                case .list:
                    EventCardView(event: event)
                case .grid:
                    EventCardGridItem(event: event)
                }
            }
            .buttonStyle(.plain)
            .onAppear {
                if event.id == events.last?.id, hasMorePages, !isLoadingMore {
                    Task { await loadMoreEvents() }
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

// MARK: - Chip Views

struct CategoryChip: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                if let icon = category.icon {
                    Text(icon)
                }
                Text(category.name)
                    .font(DS.Typography.captionMedium)
            }
            .chipStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DateChip: View {
    let label: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Text(label)
                    .font(DS.Typography.captionMedium)

                if let count {
                    Text("\(count)")
                        .font(DS.Typography.badge)
                        .padding(.horizontal, DS.Spacing.xs + 1)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.primary.opacity(DS.Opacity.overlay) : DS.Colors.fillSecondary)
                        .clipShape(Capsule())
                }
            }
            .chipStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count != nil ? "\(label), \(count!) events" : label)
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
