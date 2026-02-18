import SwiftUI

struct RatingPill: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)

            Text(String(format: "%.1f", rating))
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f out of 10 stars", rating))
    }
}
