import SwiftUI

struct MyEventsView: View {
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading your events...")
                } else if let error {
                    ContentUnavailableView {
                        Label("Something went wrong", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Try Again") { Task { await loadEvents() } }
                    }
                } else if events.isEmpty {
                    ContentUnavailableView {
                        Label("No Events Yet", systemImage: "calendar")
                    } description: {
                        Text("You haven't joined any events yet.")
                    }
                } else {
                    eventList
                }
            }
            .navigationTitle("My Events")
            .task { await loadEvents() }
            .refreshable { await loadEvents() }
        }
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(events) { event in
                    NavigationLink(value: event.slug) {
                        EventCardView(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationDestination(for: String.self) { slug in
            EventDetailView(slug: slug)
        }
    }

    private func loadEvents() async {
        isLoading = true
        error = nil

        do {
            events = try await APIClient.shared.fetchAttendingEvents()
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
