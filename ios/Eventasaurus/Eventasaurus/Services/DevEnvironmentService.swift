#if DEBUG
import Foundation

/// Manages the development environment override (localhost vs production).
/// Changing the environment requires an app restart since API clients and Clerk
/// are initialized once at launch.
@MainActor @Observable
final class DevEnvironmentService {
    static let shared = DevEnvironmentService()

    private let defaults = UserDefaults.standard
    private let key = "dev_use_production_server"

    /// What the user has selected (may differ from current if restart is pending).
    private(set) var isProductionSelected: Bool

    /// What the app is actually running against right now.
    var isRunningProduction: Bool {
        AppConfig.useProductionServer
    }

    /// True when the stored preference differs from what's running.
    var needsRestart: Bool {
        isProductionSelected != isRunningProduction
    }

    private init() {
        self.isProductionSelected = UserDefaults.standard.bool(forKey: "dev_use_production_server")
    }

    /// Toggle the environment. Clears dev auth when switching to production.
    func setProduction(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
        isProductionSelected = enabled
        if enabled {
            DevAuthService.shared.clearDevAuth()
        }
    }
}
#endif
