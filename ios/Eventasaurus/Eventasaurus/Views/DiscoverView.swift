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
    @State private var showCityPicker = false

    // Search
    @State private var searchText = ""

    // Date filtering
    @State private var selectedDateRange: String?

    // Sort options
    @State private var sortBy: String = "starts_at"
    @State private var sortOrder: String = "asc"

    private static let dateRanges: [(label: String, value: String?)] = [
        ("All", nil),
        ("Today", "today"),
        ("Tomorrow", "tomorrow"),
        ("This Weekend", "this_weekend"),
        ("Next 7 Days", "next_7_days"),
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
                        Spacer()
                    } else if let error, events.isEmpty {
                        ContentUnavailableView {
                            Label("Something went wrong", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error.localizedDescription)
                        } actions: {
                            Button("Try Again") { Task { await requestLocationAndLoad() } }
                        }
                    } else if events.isEmpty && !isLoading {
                        ContentUnavailableView {
                            Label("No Events Found", systemImage: "calendar.badge.exclamationmark")
                        } description: {
                            Text("No events match your filters. Try adjusting your search criteria.")
                        } actions: {
                            if hasActiveFilters {
                                Button("Clear Filters") {
                                    clearFilters()
                                    Task { await loadEvents() }
                                }
                            }
                        }
                    } else {
                        eventList
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCityPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedCity != nil ? "building.2" : "location.fill")
                            Text(selectedCity?.name ?? resolvedCity?.name ?? "Nearby")
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
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
                    locationDenied: locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted
                ) { city in
                    selectedCity = city
                    persistCitySelection(city)
                    Task { await loadEvents() }
                }
            }
            .task {
                restoreCitySelection()
                await loadCategories()
                await requestLocationAndLoad()
            }
            .refreshable { await requestLocationAndLoad() }
        }
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                sortOption("Date", value: "starts_at")
                sortOption("Title", value: "title")
                sortOption("Popularity", value: "popularity")
                sortOption("Relevance", value: "relevance")
            }
            Section("Order") {
                Button {
                    sortOrder = "asc"
                    Task { await loadEvents() }
                } label: {
                    Label("Ascending", systemImage: sortOrder == "asc" ? "checkmark" : "")
                }
                Button {
                    sortOrder = "desc"
                    Task { await loadEvents() }
                } label: {
                    Label("Descending", systemImage: sortOrder == "desc" ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline)
        }
    }

    private func sortOption(_ label: String, value: String) -> some View {
        Button {
            sortBy = value
            Task { await loadEvents() }
        } label: {
            Label(label, systemImage: sortBy == value ? "checkmark" : "")
        }
    }

    // MARK: - Filter Chips (pinned above event list, full-width for horizontal scroll)

    private var filterChips: some View {
        VStack(spacing: 8) {
            // Category chips
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { cat in
                            CategoryChip(
                                category: cat,
                                isSelected: selectedCategories.contains(cat.id)
                            ) {
                                toggleCategory(cat.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Date range chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.dateRanges, id: \.label) { range in
                        DateChip(
                            label: range.label,
                            isSelected: selectedDateRange == range.value
                        ) {
                            selectedDateRange = range.value
                            Task { await loadEvents() }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Event List

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(events) { event in
                    NavigationLink(value: event.destination(cityId: selectedCity?.id)) {
                        EventCardView(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
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
            }
        }
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
        // If a city is selected, skip GPS
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
            // Resolve GPS to a city name for display (structured, cancellable)
            if resolvedCity == nil {
                resolvedCity = try? await APIClient.shared.resolveCity(
                    lat: loc.coordinate.latitude, lng: loc.coordinate.longitude
                )
            }
        } else {
            isLoading = false
            error = LocationError.unavailable
        }
    }

    private func loadEvents() async {
        // Need either city or GPS coords
        if selectedCity == nil {
            guard lastLat != nil, lastLng != nil else {
                await requestLocationAndLoad()
                return
            }
        }

        isLoading = true
        error = nil

        do {
            events = try await APIClient.shared.fetchNearbyEvents(
                lat: selectedCity == nil ? lastLat : nil,
                lng: selectedCity == nil ? lastLng : nil,
                cityId: selectedCity?.id,
                categoryIds: Array(selectedCategories),
                search: searchText.isEmpty ? nil : searchText,
                dateRange: selectedDateRange,
                sortBy: sortBy == "starts_at" ? nil : sortBy,
                sortOrder: sortOrder == "asc" ? nil : sortOrder
            )
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Filter Helpers

    private var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || selectedDateRange != nil || !searchText.isEmpty
    }

    private func clearFilters() {
        selectedCategories.removeAll()
        selectedDateRange = nil
        searchText = ""
        sortBy = "starts_at"
        sortOrder = "asc"
    }

    private func toggleCategory(_ id: Int) {
        if selectedCategories.contains(id) {
            selectedCategories.remove(id)
        } else {
            selectedCategories.insert(id)
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
            HStack(spacing: 4) {
                if let icon = category.icon {
                    Text(icon)
                }
                Text(category.name)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct DateChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
