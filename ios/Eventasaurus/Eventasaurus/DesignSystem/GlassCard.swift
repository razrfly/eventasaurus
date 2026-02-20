import SwiftUI

/// A card that uses Liquid Glass on iOS 26 for translucent overlay effects.
/// Use over rich backgrounds (photos, gradients, maps) for the glassmorphic look.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = DS.Radius.xxl,
        padding: CGFloat = DS.Spacing.xl,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .glassBackground(cornerRadius: cornerRadius)
    }
}

/// A floating action bar with glass background — sticks to the bottom of the screen.
/// Designed for primary CTAs on event detail views (Register, Share, Save).
struct GlassActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .glassBackground(cornerRadius: DS.Radius.xxl)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.md)
    }
}

#Preview("GlassCard") {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue, .indigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: DS.Spacing.xl) {
            GlassCard {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text("Jazz Night at Blue Note")
                        .font(DS.Typography.title)
                    Text("Fri, Mar 14 at 8:00 PM")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                    Text("Blue Note Jazz Club, NYC")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }

            GlassCard(cornerRadius: DS.Radius.lg, padding: DS.Spacing.lg) {
                HStack {
                    Image(systemName: "thermometer.medium")
                    Text("13° Clear")
                        .font(DS.Typography.body)
                    Spacer()
                    Text("Weather")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

#Preview("GlassActionBar") {
    ZStack(alignment: .bottom) {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        GlassActionBar {
            HStack(spacing: DS.Spacing.lg) {
                Button {
                } label: {
                    Text("Register")
                        .font(DS.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }

                Button {
                } label: {
                    Image(systemName: "bookmark")
                }
            }
        }
    }
}
