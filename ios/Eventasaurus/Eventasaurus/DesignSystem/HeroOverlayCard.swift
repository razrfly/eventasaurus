import SwiftUI

/// Clear glass card positioned at the bottom of a hero image.
/// Uses `.clearGlassBackground()` (Glass.clear on iOS 26) which is designed
/// for overlaying photo content — lets the image show through while providing text contrast.
struct HeroOverlayCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clearGlassBackground(cornerRadius: DS.Radius.xl)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
    }
}
