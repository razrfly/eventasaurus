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
                if data.container.coverImageUrl != nil {
                    CachedImage(
                        url: data.container.coverImageUrl.flatMap { URL(string: $0) },
                        height: 220,
                        cornerRadius: 0,
                        placeholderIcon: "sparkles"
                    )
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

                    // Source link
                    if let sourceUrl = data.container.sourceUrl, let url = URL(string: sourceUrl) {
                        ExternalLinkButton(title: "View Source", url: url, icon: "arrow.up.right.square")
                    }

                    Divider()

                    // Events
                    if data.events.isEmpty {
                        Text("No events in this \(data.container.containerType)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Events")
                                .font(.headline)
                            Spacer()
                            if let count = data.container.eventCount {
                                Text("\(count) event\(count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

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
