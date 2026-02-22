import CoreLocation
import SwiftUI
import MapKit

struct VenueSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [UserEventVenue] = []
    @State private var recentVenues: [RecentVenue] = []
    @State private var isSearching = false
    @State private var isLoadingRecent = true
    @State private var showCreateForm = false
    @State private var searchTask: Task<Void, Never>?

    // Create venue form
    @State private var newVenueName = ""
    @State private var newVenueAddress = ""
    @State private var mapSearchService = MapKitSearchService()
    @State private var selectedMapResult: MapKitSearchResult?
    @State private var isSettingResolvedAddress = false
    @State private var isCreatingVenue = false
    @State private var error: String?

    var selectedVenue: UserEventVenue?
    var onSelect: (UserEventVenue?) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let selectedVenue {
                    currentVenueSection(selectedVenue)
                }

                if !showCreateForm {
                    if !searchText.isEmpty {
                        searchResultsSection
                    } else {
                        recentVenuesSection
                    }

                    createNewSection
                } else {
                    createVenueFormSection
                }
            }
            .searchable(text: $searchText, prompt: "Search venues...")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
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
            .navigationTitle("Select Venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadRecentVenues() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func currentVenueSection(_ venue: UserEventVenue) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(venue.name)
                        .font(DS.Typography.bodyMedium)
                    if let address = venue.address {
                        Text(address)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Button(role: .destructive) {
                onSelect(nil)
                dismiss()
            } label: {
                Label("Remove Venue", systemImage: "xmark.circle")
            }
        } header: {
            Text("Current Venue")
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        Section {
            if isSearching {
                HStack {
                    ProgressView()
                    Text("Searching...")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            } else if searchResults.isEmpty {
                Text("No venues found")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(searchResults) { venue in
                    Button {
                        onSelect(venue)
                        dismiss()
                    } label: {
                        venueRow(name: venue.name, address: venue.address)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Search Results")
        }
    }

    @ViewBuilder
    private var recentVenuesSection: some View {
        if !recentVenues.isEmpty {
            Section {
                ForEach(recentVenues) { recent in
                    Button {
                        let venue = UserEventVenue(
                            id: recent.id,
                            name: recent.name,
                            address: recent.address,
                            latitude: recent.latitude,
                            longitude: recent.longitude
                        )
                        onSelect(venue)
                        dismiss()
                    } label: {
                        HStack {
                            venueRow(name: recent.name, address: recent.address)
                            Spacer()
                            Text("\(recent.usageCount)x")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xxs)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Recent Venues")
            }
        }
    }

    private var createNewSection: some View {
        Section {
            Button {
                withAnimation { showCreateForm = true }
            } label: {
                Label("Create New Venue", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var createVenueFormSection: some View {
        Section {
            TextField("Venue Name", text: $newVenueName)
                .font(DS.Typography.body)

            TextField("Address", text: $newVenueAddress)
                .font(DS.Typography.body)
                .onChange(of: newVenueAddress) { _, newValue in
                    // Don't clear selection or re-search when we programmatically set address from a resolved suggestion
                    guard !isSettingResolvedAddress else { return }
                    selectedMapResult = nil
                    mapSearchService.search(query: newValue)
                }

            if !mapSearchService.suggestions.isEmpty && selectedMapResult == nil {
                // Show up to 3 suggestions to avoid flooding the form
                ForEach(mapSearchService.suggestions.prefix(3), id: \.self) { suggestion in
                    Button {
                        Task {
                            if let result = await mapSearchService.resolve(suggestion) {
                                isSettingResolvedAddress = true
                                selectedMapResult = result
                                newVenueAddress = result.address
                                if newVenueName.isEmpty {
                                    newVenueName = result.name
                                }
                                isSettingResolvedAddress = false
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(suggestion.title)
                                .font(DS.Typography.body)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Let users dismiss suggestions and use their typed text as-is
                Button {
                    mapSearchService.suggestions = []
                } label: {
                    Text("Use address as entered")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.blue)
                }
            }

            if selectedMapResult != nil {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.red)
                    Text("Location set")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        selectedMapResult = nil
                    }
                    .font(DS.Typography.caption)
                }
            }

            if let error {
                Text(error)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await createAndSelectVenue() }
            } label: {
                HStack {
                    Spacer()
                    if isCreatingVenue {
                        ProgressView()
                            .padding(.trailing, DS.Spacing.xs)
                    }
                    Text(isCreatingVenue ? "Creating..." : "Create Venue")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(!canCreateVenue || isCreatingVenue)

            Button("Back to Search") {
                withAnimation { showCreateForm = false }
            }
        } header: {
            Text("New Venue")
        }
    }

    /// Allow creating a venue if either name or address is provided (matches web behavior)
    private var canCreateVenue: Bool {
        !newVenueName.trimmingCharacters(in: .whitespaces).isEmpty ||
        !newVenueAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Helpers

    private func venueRow(name: String, address: String?) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .font(DS.Typography.bodyMedium)
                if let address, !address.isEmpty {
                    Text(address)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadRecentVenues() async {
        defer { isLoadingRecent = false }
        do {
            recentVenues = try await GraphQLClient.shared.fetchRecentVenues()
        } catch {
            #if DEBUG
            print("[VenueSearchSheet] Failed to load recent venues: \(error)")
            #endif
        }
    }

    private func performSearch(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        do {
            searchResults = try await GraphQLClient.shared.searchVenues(query: query)
            isSearching = false
        } catch is CancellationError {
            // Leave isSearching true so the replacement task manages loading state
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Leave isSearching true so the replacement task manages loading state
            return
        } catch {
            searchResults = []
            isSearching = false
            #if DEBUG
            print("[VenueSearchSheet] Search failed: \(error)")
            #endif
        }
    }

    private func createAndSelectVenue() async {
        isCreatingVenue = true
        defer { isCreatingVenue = false }
        error = nil

        // If name is empty but address is provided, use address as name (matches web behavior)
        let name = newVenueName.trimmingCharacters(in: .whitespaces)
        let address = newVenueAddress.trimmingCharacters(in: .whitespaces)
        let effectiveName = name.isEmpty ? address : name

        // Use MapKit result if available, otherwise geocode the typed address
        var latitude = selectedMapResult?.latitude
        var longitude = selectedMapResult?.longitude
        var cityName = selectedMapResult?.cityName
        var countryCode = selectedMapResult?.countryCode

        if selectedMapResult == nil && !address.isEmpty {
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.geocodeAddressString(address),
               let placemark = placemarks.first {
                latitude = placemark.location?.coordinate.latitude
                longitude = placemark.location?.coordinate.longitude
                cityName = placemark.locality
                countryCode = placemark.isoCountryCode
            }
        }

        do {
            let venue = try await GraphQLClient.shared.createVenue(
                name: effectiveName,
                address: address.isEmpty ? nil : address,
                latitude: latitude,
                longitude: longitude,
                cityName: cityName,
                countryCode: countryCode
            )
            onSelect(venue)
            dismiss()
        } catch let createError {
            if let mutationError = createError as? GraphQLMutationError {
                self.error = mutationError.localizedDescription
            } else if let urlError = createError as? URLError {
                self.error = urlError.code == .notConnectedToInternet
                    ? "No internet connection. Please check your network and try again."
                    : "Network error. Please try again."
            } else {
                self.error = "Failed to create venue. Please try again."
            }
        }
    }
}
