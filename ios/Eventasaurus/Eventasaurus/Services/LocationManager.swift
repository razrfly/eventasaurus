import CoreLocation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var location: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var error: Error?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    /// Async helper: waits for a location fix with timeout.
    /// Returns nil if location can't be determined within the timeout.
    func getLocation(timeout: TimeInterval = 10) async -> CLLocation? {
        // Already have a location
        if let location { return location }

        // Request permission if needed
        if authorizationStatus == .notDetermined {
            requestPermission()
        }

        // Poll for location with timeout (checking every 250ms)
        var locationRequested = false
        let attempts = Int(timeout / 0.25)
        for _ in 0..<attempts {
            try? await Task.sleep(for: .milliseconds(250))

            // Check if permission was denied
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                return nil
            }

            // Request location once after authorization (single request to avoid queuing duplicates)
            if !locationRequested && location == nil &&
                (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways) {
                locationRequested = true
                requestLocation()
            }

            if let location { return location }
        }

        return nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = error
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
