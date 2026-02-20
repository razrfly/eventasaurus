import SwiftUI

/// Animated loading skeleton placeholder that shimmers.
struct LoadingSkeleton: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var shimmer = false

    init(
        width: CGFloat? = nil,
        height: CGFloat = 20,
        cornerRadius: CGFloat = DS.Radius.md
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color(.systemGray4).opacity(0.5),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmer ? geometry.size.width * 1.2 : -geometry.size.width * 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .frame(width: width, height: height)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmer = true
                }
            }
    }
}

/// Card-shaped loading skeleton for event feed
struct EventCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            LoadingSkeleton(height: DS.ImageSize.cardCover, cornerRadius: DS.Radius.lg)
            LoadingSkeleton(width: 200, height: 18, cornerRadius: DS.Radius.xs)
            LoadingSkeleton(width: 140, height: 14, cornerRadius: DS.Radius.xs)
            LoadingSkeleton(width: 160, height: 14, cornerRadius: DS.Radius.xs)
        }
        .padding(DS.Spacing.xl)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
        .dsShadow(DS.Shadow.card)
    }
}

#Preview("Loading Skeletons") {
    VStack(spacing: DS.Spacing.xl) {
        EventCardSkeleton()
        EventCardSkeleton()
    }
    .padding()
}
