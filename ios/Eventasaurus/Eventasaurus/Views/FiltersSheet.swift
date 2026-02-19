import SwiftUI

struct FilterCategoryItem: Identifiable {
    let id: Int
    let name: String
    let icon: String?
    let color: Color
}

struct FiltersSheet: View {
    @Binding var radiusKm: Double
    @Binding var sortBy: String
    @Binding var sortOrder: String
    @Binding var selectedCategories: Set<Int>
    @Binding var language: String
    let categoryItems: [FilterCategoryItem]
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    private static let radiusOptions: [Double] = [5, 10, 25, 50, 100]

    var body: some View {
        NavigationStack {
            Form {
                radiusSection
                sortSection
                languageSection
                categoriesSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        radiusKm = 50
                        sortBy = "starts_at"
                        sortOrder = "asc"
                        selectedCategories.removeAll()
                        language = "en"
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        dismiss()
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var radiusSection: some View {
        Section("Search Radius") {
            Picker("Radius", selection: $radiusKm) {
                ForEach(Self.radiusOptions, id: \.self) { km in
                    Text("\(Int(km)) km").tag(km)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var sortSection: some View {
        Section("Sort By") {
            Picker("Sort By", selection: $sortBy) {
                Text("Date").tag("starts_at")
                Text("Title").tag("title")
                Text("Popularity").tag("popularity")
                Text("Relevance").tag("relevance")
            }
            .pickerStyle(.menu)

            Picker("Order", selection: $sortOrder) {
                Text("Ascending").tag("asc")
                Text("Descending").tag("desc")
            }
            .pickerStyle(.segmented)
        }
    }

    private var languageSection: some View {
        Section("Language") {
            Picker("Language", selection: $language) {
                Text("English").tag("en")
                Text("Polski").tag("pl")
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var categoriesSection: some View {
        if !categoryItems.isEmpty {
            Section("Categories") {
                ForEach(categoryItems) { item in
                    categoryRow(item)
                }
            }
        }
    }

    private func categoryRow(_ item: FilterCategoryItem) -> some View {
        Button {
            if selectedCategories.contains(item.id) {
                selectedCategories.remove(item.id)
            } else {
                selectedCategories.insert(item.id)
            }
        } label: {
            HStack {
                if let icon = item.icon {
                    Text(icon)
                }

                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)

                Text(item.name)
                    .foregroundStyle(.primary)

                Spacer()

                if selectedCategories.contains(item.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
