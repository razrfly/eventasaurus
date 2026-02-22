import Foundation
import MapKit

struct MapKitSearchResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let cityName: String?
    let countryCode: String?
}

@MainActor
@Observable
final class MapKitSearchService: NSObject {
    var suggestions: [MKLocalSearchCompletion] = []
    var isSearching = false

    private let completer = MKLocalSearchCompleter()
    private var continuation: AsyncStream<[MKLocalSearchCompletion]>.Continuation?
    private var stream: AsyncStream<[MKLocalSearchCompletion]>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(query: String) {
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        isSearching = true
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> MapKitSearchResult? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else { return nil }
            let placemark = item.placemark
            let address = [
                placemark.thoroughfare,
                placemark.subThoroughfare,
                placemark.locality,
                placemark.administrativeArea,
                placemark.postalCode,
                placemark.country
            ].compactMap { $0 }.joined(separator: ", ")

            return MapKitSearchResult(
                name: item.name ?? completion.title,
                address: address,
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude,
                cityName: placemark.locality,
                countryCode: placemark.countryCode
            )
        } catch {
            return nil
        }
    }
}

extension MapKitSearchService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.suggestions = results
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
}
