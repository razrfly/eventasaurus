import SwiftUI

struct EventDetailView: View {
    let slug: String
    @State private var event: Event?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let event {
                eventContent(event)
            } else if let error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEvent() }
    }

    private func eventContent(_ event: Event) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Cover image
                if let imageUrl = event.coverImageUrl, let url = URL(string: imageUrl) {
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
                    Text(event.title)
                        .font(.title2.bold())

                    // Date & time
                    if let date = event.startsAt {
                        Label {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(.subheadline)
                    }

                    // Venue
                    if let venue = event.venue {
                        Label {
                            VStack(alignment: .leading) {
                                Text(venue.name)
                                    .font(.subheadline)
                                if let address = venue.address {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }

                    // Attendee count
                    if let count = event.attendeeCount {
                        Label("\(count) attending", systemImage: "person.2")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Categories
                    if let categories = event.categories, !categories.isEmpty {
                        HStack {
                            ForEach(categories, id: \.self) { category in
                                Text(category)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.tint.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    Divider()

                    // Description
                    if let description = event.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadEvent() async {
        do {
            event = try await APIClient.shared.fetchEventDetail(slug: slug)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}
