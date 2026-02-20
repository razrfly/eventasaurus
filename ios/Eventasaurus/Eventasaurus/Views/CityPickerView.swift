import SwiftUI
import os

struct CityPickerView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.wombie.app", category: "CityPickerView")
    private static let recentCitiesKey = "recentCities"
    private static let maxRecentCities = 5
    private static let eventCountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var popularCities: [City] = []
    @State private var searchResults: [City] = []
    @State private var recentCities: [City] = []
    @State private var isLoading = false
    @State private var popularCitiesLoaded = false

    let selectedCity: City?
    let resolvedCity: City?
    let locationDenied: Bool
    let locationResolved: Bool
    let onSelect: (City?) -> Void

    var body: some View {
        NavigationStack {
            List {
                if searchText.count < 2 {
                    browseContent
                } else {
                    searchContent
                }
            }
            .navigationTitle("Choose City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search cities...")
            .task {
                loadRecentCities()
                await loadPopularCities()
            }
            .task(id: searchText) {
                guard searchText.count >= 2 else {
                    searchResults = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await performSearch()
            }
        }
    }

    // MARK: - Client-side filtering for 1-char search

    private var filteredPopularCities: [City] {
        guard searchText.count == 1 else { return popularCities }
        return popularCities.filter { $0.name.localizedStandardContains(searchText) }
    }

    private var filteredRecentCities: [City] {
        guard searchText.count == 1 else { return recentCities }
        return recentCities.filter { $0.name.localizedStandardContains(searchText) }
    }

    // MARK: - Browse Content (empty / 1-char search)

    @ViewBuilder
    private var browseContent: some View {
        // Current Location section
        Section {
            if locationDenied {
                HStack {
                    Image(systemName: "location.slash.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("Location Unavailable")
                        Button("Enable in Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(DS.Typography.caption)
                    }
                    Spacer()
                }
            } else {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text("Use My Location")
                            if let resolved = resolvedCity {
                                Text(citySubtitle(resolved))
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(.secondary)
                            } else if !locationResolved {
                                HStack(spacing: DS.Spacing.xs) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("Detecting location...")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if selectedCity == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }

        // Popular Cities section
        Section("Popular Cities") {
            if !popularCitiesLoaded {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if popularCities.isEmpty {
                Text("No popular cities available")
                    .foregroundStyle(.secondary)
            } else if filteredPopularCities.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredPopularCities) { city in
                    cityRow(city, showEventCount: true)
                }
            }
        }

        // Recently Selected section
        if !filteredRecentCities.isEmpty {
            Section {
                ForEach(filteredRecentCities) { city in
                    cityRow(city, showEventCount: false)
                }
                if searchText.isEmpty {
                    Button("Clear Recent", role: .destructive) {
                        clearRecentCities()
                    }
                    .font(DS.Typography.body)
                }
            } header: {
                Text("Recently Selected")
            }
        }
    }

    // MARK: - Search Content (2+ chars)

    @ViewBuilder
    private var searchContent: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if searchResults.isEmpty {
            Text("No cities found")
                .foregroundStyle(.secondary)
        } else {
            let grouped = Dictionary(grouping: searchResults) { $0.country ?? "Other" }
            let sortedKeys = grouped.keys.sorted()

            ForEach(sortedKeys, id: \.self) { country in
                Section(country) {
                    ForEach(grouped[country] ?? []) { city in
                        cityRow(city, showEventCount: false)
                    }
                }
            }
        }
    }

    // MARK: - City Row

    private func cityRow(_ city: City, showEventCount: Bool) -> some View {
        Button {
            selectCity(city)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(city.name)
                    if showEventCount, let count = city.eventCount {
                        Text(formatEventCount(count))
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    } else if let subtitle = citySubtitleOrNil(city) {
                        Text(subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selectedCity?.id == city.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Helpers

    private func citySubtitle(_ city: City) -> String {
        city.country ?? ""
    }

    private func citySubtitleOrNil(_ city: City) -> String? {
        city.country
    }

    private func formatEventCount(_ count: Int) -> String {
        let formatted = Self.eventCountFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(formatted) \(count == 1 ? "event" : "events")"
    }

    private func selectCity(_ city: City) {
        addToRecentCities(city)
        onSelect(city)
        dismiss()
    }

    // MARK: - Data Loading

    private func loadPopularCities() async {
        do {
            popularCities = try await APIClient.shared.fetchPopularCities()
        } catch {
            Self.logger.error("Failed to load popular cities: \(error, privacy: .public)")
        }
        popularCitiesLoaded = true
    }

    private func performSearch() async {
        isLoading = true
        defer { isLoading = false }

        do {
            searchResults = try await APIClient.shared.searchCities(query: searchText)
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Failed to search cities: \(error, privacy: .public)")
            searchResults = []
        }
    }

    // MARK: - Recent Cities Persistence

    private func loadRecentCities() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentCitiesKey) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        recentCities = (try? decoder.decode([City].self, from: data)) ?? []
    }

    private func addToRecentCities(_ city: City) {
        var recents = recentCities.filter { $0.id != city.id }
        recents.insert(city, at: 0)
        if recents.count > Self.maxRecentCities {
            recents = Array(recents.prefix(Self.maxRecentCities))
        }
        recentCities = recents
        persistRecentCities(recents)
    }

    private func clearRecentCities() {
        recentCities = []
        UserDefaults.standard.removeObject(forKey: Self.recentCitiesKey)
    }

    private func persistRecentCities(_ cities: [City]) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let data = try? encoder.encode(cities) {
            UserDefaults.standard.set(data, forKey: Self.recentCitiesKey)
        }
    }
}
