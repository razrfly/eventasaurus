import SwiftUI

struct ContainerDetailView: View {
    let slug: String
    @State private var response: ContainerDetailResponse?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let response {
                containerContent(response)
            } else if let error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadContainer() }
    }

    private func containerContent(_ data: ContainerDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Cover image
                if let imageUrl = data.container.coverImageUrl, let url = URL(string: imageUrl) {
                    Color.clear
                        .frame(height: 220)
                        .overlay {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(.quaternary)
                            }
                        }
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 12) {
                    // Title
                    Text(data.container.title)
                        .font(.title2.bold())

                    // Type badge + date range
                    HStack(spacing: 8) {
                        Text(data.container.containerType.capitalized)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.1))
                            .clipShape(Capsule())

                        if let start = data.container.startDate {
                            if let end = data.container.endDate {
                                Text("\(start, format: .dateTime.month(.abbreviated).day()) – \(end, format: .dateTime.month(.abbreviated).day())")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(start, format: .dateTime.month(.abbreviated).day())
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Description
                    if let description = data.container.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                    }

                    Divider()

                    // Events
                    if data.events.isEmpty {
                        Text("No events in this \(data.container.containerType)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Events")
                            .font(.headline)

                        LazyVStack(spacing: 16) {
                            ForEach(data.events) { event in
                                NavigationLink(value: EventDestination.event(slug: event.slug)) {
                                    EventCardView(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadContainer() async {
        do {
            response = try await APIClient.shared.fetchContainerDetail(slug: slug)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            self.error = error
            isLoading = false
        }
    }
}
