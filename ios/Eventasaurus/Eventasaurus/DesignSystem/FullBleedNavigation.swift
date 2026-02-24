import SwiftUI

// MARK: - Full-Bleed Navigation

/// Hides the NavigationStack toolbar so the ScrollView frame extends to
/// the status-bar edge, letting DramaticHero's `.ignoresSafeArea(edges: .top)`
/// work correctly. Glass back/trailing buttons sit in a ZStack above the
/// content so ScrollView gestures don't intercept their taps.

private struct FullBleedNavigation<Trailing: View>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let trailing: () -> Trailing

    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                            .frame(width: 44, height: 44)
                    }
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())

                    Spacer()

                    trailing()
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.sm)

                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    /// Full-bleed hero navigation with an optional trailing view (e.g. ShareLink).
    func fullBleedNavigation<Trailing: View>(
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        modifier(FullBleedNavigation(trailing: trailing))
    }

    /// Full-bleed hero navigation with only a back button.
    func fullBleedNavigation() -> some View {
        modifier(FullBleedNavigation { EmptyView() })
    }
}
