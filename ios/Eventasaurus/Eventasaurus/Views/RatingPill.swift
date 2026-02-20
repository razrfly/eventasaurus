import SwiftUI

struct RatingPill: View {
    let rating: Double

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "star.fill")
                .foregroundStyle(DS.Colors.ratingFill)

            Text(String(format: "%.1f", rating))
        }
        .glassBadgeStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f out of 10 stars", rating))
    }
}
