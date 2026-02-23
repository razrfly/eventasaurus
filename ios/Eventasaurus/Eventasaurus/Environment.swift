import Foundation

enum AppConfig {
    #if DEBUG
    /// Whether the app is running against production (set via Dev Settings, requires restart).
    static let useProductionServer: Bool = {
        return UserDefaults.standard.bool(forKey: "dev_use_production_server")
    }()

    static let apiBaseURL: URL = {
        useProductionServer ? plistURL("APIBaseURLProd") : plistURL("APIBaseURL")
    }()

    static let clerkPublishableKey: String = {
        useProductionServer ? plistString("ClerkPublishableKeyProd") : plistString("ClerkPublishableKey")
    }()
    #else
    static let useProductionServer = true
    static let apiBaseURL = plistURL("APIBaseURLProd")
    static let clerkPublishableKey = plistString("ClerkPublishableKeyProd")
    #endif

    #if DEBUG
    /// Human-readable environment name for UI display.
    static var environmentName: String {
        useProductionServer ? "Production" : "Development"
    }

    /// Host string for UI display, derived from apiBaseURL.
    static var environmentHost: String {
        let url = apiBaseURL
        if let host = url.host {
            if let port = url.port, ![80, 443].contains(port) {
                return "\(host):\(port)"
            }
            return host
        }
        return useProductionServer ? "wombie.com" : "localhost:4000"
    }
    #endif

    private static func plistString(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("\(key) not configured in Info.plist")
        }
        return value
    }

    private static func plistURL(_ key: String) -> URL {
        guard let url = URL(string: plistString(key)) else {
            fatalError("\(key) is not a valid URL")
        }
        return url
    }
}
