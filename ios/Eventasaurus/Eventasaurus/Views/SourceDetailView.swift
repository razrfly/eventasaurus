import SwiftUI

struct SourceDetailView: View {
    let slug: String
    let cityId: Int?
    @State private var response: SourceDetailResponse?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let response {
                sourceContent(response)
            } else if let error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSource() }
    }

    private func sourceContent(_ data: SourceDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Source header
                HStack(spacing: 12) {
                    if let logoUrl = data.source.logoUrl, let url = URL(string: logoUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Text(data.source.name)
                        .font(.title2.bold())
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Events list
                if data.events.isEmpty {
                    ContentUnavailableView {
                        Label("No Events", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("No upcoming events from this source.")
                    }
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(data.events) { event in
                            NavigationLink(value: EventDestination.event(slug: event.slug)) {
                                EventCardView(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
    }

    private func loadSource() async {
        do {
            response = try await APIClient.shared.fetchSourceDetail(slug: slug, cityId: cityId)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
