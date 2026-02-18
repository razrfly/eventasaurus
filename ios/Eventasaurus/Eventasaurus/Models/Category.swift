import SwiftUI

struct CategoriesResponse: Codable {
    let categories: [Category]
}

struct Category: Codable, Identifiable, Hashable {
    /// Present when fetched from /categories endpoint, absent when embedded in events
    let numericId: Int?
    let name: String
    let slug: String
    let icon: String?
    let color: String?

    /// Stable identity using slug — works for both fetched and embedded categories
    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case numericId = "id"
        case name, slug, icon, color
    }

    /// Resolved SwiftUI color from hex string, falls back to .blue
    var resolvedColor: Color {
        Color(hex: color) ?? .blue
    }
}

// MARK: - Slugification

extension String {
    /// Convert a display name to a URL-safe slug: strip diacritics, remove punctuation,
    /// collapse whitespace, lowercase, and join with hyphens.
    func slugified() -> String {
        self.folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
    }
}

// MARK: - Hex Color Extension

extension Color {
    /// Initialize a Color from an optional hex string (e.g. "#3B82F6" or "3B82F6").
    /// Returns nil if the string is nil or not a valid 6-digit hex.
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
