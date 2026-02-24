import SwiftUI

/// Reusable hero section with taller image, 3-stop gradient, and clear glass overlay.
/// Bleeds under the navigation bar via `.ignoresSafeArea(edges: .top)`.
struct DramaticHero<Overlay: View>: View {
    let imageURL: URL?
    var height: CGFloat = DS.ImageSize.heroLarge
    var placeholderIcon: String = "calendar"
    @ViewBuilder let overlay: () -> Overlay

    var body: some View {
        ZStack(alignment: .bottom) {
            CachedImage(
                url: imageURL,
                height: height,
                cornerRadius: 0,
                placeholderIcon: placeholderIcon
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.2), .black.opacity(DS.Opacity.heroGradient)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height * 3 / 4)

            overlay()
        }
        .ignoresSafeArea(edges: .top)
    }
}
