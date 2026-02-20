import SwiftUI

// MARK: - Shadow Modifier

extension View {
    /// Apply a DS shadow style
    func dsShadow(_ style: DS.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Glass Modifier (iOS 26)

extension View {
    /// Apply glassmorphic background using Liquid Glass on iOS 26+,
    /// falls back to ultraThinMaterial on earlier versions.
    @ViewBuilder
    func glassBackground(
        cornerRadius: CGFloat = DS.Radius.xxl,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = interactive ? .regular.interactive() : .regular
            self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Apply clear glass (for use over photos/maps) — iOS 26 only,
    /// falls back to thin material.
    @ViewBuilder
    func clearGlassBackground(
        cornerRadius: CGFloat = DS.Radius.xxl
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Badge/Pill Modifier

extension View {
    /// Standard capsule badge styling (category pills, time badges, etc.)
    func badgeStyle(
        backgroundColor: Color = .blue,
        foregroundColor: Color = .white
    ) -> some View {
        self
            .font(DS.Typography.badge)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    /// Glass capsule badge — for badges that should be translucent
    func glassBadgeStyle() -> some View {
        self
            .font(DS.Typography.badge)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .glassBackground(cornerRadius: 99, interactive: false)
    }

    /// Chip/filter style (category chips, date chips)
    func chipStyle(isSelected: Bool, selectedColor: Color = .blue) -> some View {
        self
            .font(isSelected ? DS.Typography.captionBold : DS.Typography.caption)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(isSelected ? selectedColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}

// MARK: - Card Modifier

extension View {
    /// Standard card container with background and shadow
    func cardStyle(cornerRadius: CGFloat = DS.Radius.xl) -> some View {
        self
            .padding(DS.Spacing.xl)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .dsShadow(DS.Shadow.card)
    }

    /// Glass card — translucent card for overlay on rich backgrounds
    func glassCardStyle(cornerRadius: CGFloat = DS.Radius.xxl) -> some View {
        self
            .padding(DS.Spacing.xl)
            .glassBackground(cornerRadius: cornerRadius)
    }
}
