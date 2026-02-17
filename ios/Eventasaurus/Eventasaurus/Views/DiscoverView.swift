import SwiftUI

struct DiscoverView: View {
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var locationManager = LocationManager()
    @State private var lastLat: Double?
    @State private var lastLng: Double?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Finding events nearby...")
                } else if let error {
                    ContentUnavailableView {
                        Label("Something went wrong", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Try Again") { Task { await requestLocationAndLoad() } }
                    }
                } else if events.isEmpty {
                    ContentUnavailableView {
                        Label("No Events Nearby", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("No events found near your location. Try a wider search area.")
                    }
                } else {
                    eventList
                }
            }
            .navigationTitle("Discover")
            .task { await requestLocationAndLoad() }
            .refreshable { await requestLocationAndLoad() }
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

    private func requestLocationAndLoad() async {
        isLoading = true
        error = nil

        // Use cached location or wait for a new fix
        let loc = locationManager.location != nil
            ? locationManager.location
            : await locationManager.getLocation(timeout: 10)

        if let loc {
            lastLat = loc.coordinate.latitude
            lastLng = loc.coordinate.longitude
            await loadEvents()
        } else {
            isLoading = false
            error = LocationError.unavailable
        }
    }

    private func loadEvents() async {
        guard let lat = lastLat, let lng = lastLng else {
            await requestLocationAndLoad()
            return
        }

        isLoading = true
        error = nil

        do {
            events = try await APIClient.shared.fetchNearbyEvents(lat: lat, lng: lng)
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

enum LocationError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Unable to determine your location. Please check location permissions in Settings."
        }
    }
}
