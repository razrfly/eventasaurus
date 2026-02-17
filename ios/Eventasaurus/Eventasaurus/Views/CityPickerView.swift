import SwiftUI

struct CityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var cities: [City] = []
    @State private var isLoading = false

    let selectedCity: City?
    let onSelect: (City?) -> Void

    var body: some View {
        NavigationStack {
            List {
                // "Use My Location" option
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                        Text("Use My Location")
                        Spacer()
                        if selectedCity == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // City list
                Section {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if cities.isEmpty {
                        Text("No cities found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(cities) { city in
                            Button {
                                onSelect(city)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(city.name)
                                        if let country = city.country {
                                            Text(country)
                                                .font(.caption)
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
                    }
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
            .onChange(of: searchText) {
                Task { await loadCities() }
            }
            .task { await loadCities() }
        }
    }

    private func loadCities() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let query = searchText.count >= 2 ? searchText : nil
            cities = try await APIClient.shared.searchCities(query: query)
        } catch {
            cities = []
        }
    }
}
