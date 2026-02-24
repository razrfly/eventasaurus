import SwiftUI

/// Primary action button using Liquid Glass on iOS 26.
/// Falls back to ultraThinMaterial on earlier versions via glassBackground().
struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.bodyBold)
            .padding(.horizontal, DS.Spacing.xxl)
            .padding(.vertical, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .glassBackground(cornerRadius: DS.Radius.xl, interactive: true)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Secondary action button — glass capsule, compact.
struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.bodyMedium)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.md)
            .glassBackground(cornerRadius: DS.Radius.full, interactive: true)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Icon-only glass button (share, bookmark, etc.)
struct GlassIconButtonStyle: ButtonStyle {
    let size: CGFloat

    init(size: CGFloat = 44) {
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .glassBackground(cornerRadius: size / 2, interactive: true)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Tinted capsule button for stateful actions (RSVP, Plan with Friends).
/// When active, a colored fill sits behind the capsule; when inactive, a subtle tint.
/// Does NOT add its own glass effect — works cleanly both standalone and inside glass containers
/// (e.g. GlassActionBar) without glass-on-glass artifacts.
struct GlassTintedButtonStyle: ButtonStyle {
    let tintColor: Color
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.bodyMedium)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.md)
            .foregroundStyle(isActive ? .white : tintColor)
            .background(
                isActive ? tintColor : tintColor.opacity(0.12),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

extension ButtonStyle where Self == GlassPrimaryButtonStyle {
    static var glassPrimary: GlassPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == GlassSecondaryButtonStyle {
    static var glassSecondary: GlassSecondaryButtonStyle { .init() }
}

extension ButtonStyle where Self == GlassIconButtonStyle {
    static var glassIcon: GlassIconButtonStyle { .init() }
}

extension ButtonStyle where Self == GlassTintedButtonStyle {
    static func glassTinted(_ color: Color, isActive: Bool) -> GlassTintedButtonStyle {
        .init(tintColor: color, isActive: isActive)
    }
}

#Preview("Glass Buttons") {
    ZStack {
        LinearGradient(
            colors: [.indigo, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: DS.Spacing.xxl) {
            Button("Register for Event") {}
                .buttonStyle(.glassPrimary)

            Button("Share Event") {}
                .buttonStyle(.glassSecondary)

            HStack(spacing: DS.Spacing.xl) {
                Button {} label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.glassIcon)

                Button {} label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.glassIcon)

                Button {} label: {
                    Image(systemName: "heart")
                }
                .buttonStyle(.glassIcon)
            }
        }
        .padding()
    }
}
