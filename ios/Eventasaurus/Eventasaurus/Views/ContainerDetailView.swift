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

                        let grouped = groupEventsByDate(data.events)
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(grouped, id: \.0) { dateKey, events in
                                Section {
                                    ForEach(events) { event in
                                        NavigationLink(value: EventDestination.event(slug: event.slug)) {
                                            EventCardView(event: event)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } header: {
                                    Text(formatDateGroupHeader(dateKey))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private func groupEventsByDate(_ events: [Event]) -> [(String, [Event])] {
        var groups: [String: [Event]] = [:]

        for event in events {
            if let date = event.startsAt {
                let key = Self.isoDateFormatter.string(from: date)
                groups[key, default: []].append(event)
            } else {
                groups["TBD", default: []].append(event)
            }
        }

        return groups.sorted { a, b in
            if a.key == "TBD" { return false }
            if b.key == "TBD" { return true }
            return a.key < b.key
        }
    }

    private func formatDateGroupHeader(_ isoDate: String) -> String {
        if isoDate == "TBD" { return "Date TBD" }

        guard let date = Self.isoDateFormatter.date(from: isoDate) else { return isoDate }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today, \(Self.monthDayFormatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow, \(Self.monthDayFormatter.string(from: date))"
        } else {
            return Self.fullDateFormatter.string(from: date)
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
