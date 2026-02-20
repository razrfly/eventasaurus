import Foundation

enum AppConfig {
    #if targetEnvironment(simulator)
    static let apiBaseURL = plistURL("APIBaseURL")
    static let clerkPublishableKey = plistString("ClerkPublishableKey")
    #else
    static let apiBaseURL = plistURL("APIBaseURLProd")
    static let clerkPublishableKey = plistString("ClerkPublishableKeyProd")
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
