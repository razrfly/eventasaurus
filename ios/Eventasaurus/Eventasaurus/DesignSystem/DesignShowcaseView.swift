#if DEBUG
import SwiftUI

/// Preview-only showcase demonstrating all DS tokens and components.
struct DesignShowcaseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxxl) {
                typographySection
                spacingSection
                radiusSection
                colorSection
                shadowSection
                badgeSection
                chipSection
                glassSection
            }
            .padding(DS.Spacing.xl)
        }
        .navigationTitle("Design System")
    }

    // MARK: - Typography

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Typography")
            Text("Display").font(DS.Typography.display)
            Text("Title").font(DS.Typography.title)
            Text("Title Secondary").font(DS.Typography.titleSecondary)
            Text("Heading").font(DS.Typography.heading)
            Text("Body").font(DS.Typography.body)
            Text("Body Medium").font(DS.Typography.bodyMedium)
            Text("Body Bold").font(DS.Typography.bodyBold)
            Text("Body Italic").font(DS.Typography.bodyItalic)
            Text("Prose").font(DS.Typography.prose)
            Text("Caption").font(DS.Typography.caption)
            Text("Caption Bold").font(DS.Typography.captionBold)
            Text("Badge").font(DS.Typography.badge)
            Text("Micro").font(DS.Typography.micro)
        }
    }

    // MARK: - Spacing

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Spacing")
            spacingRow("xxs", DS.Spacing.xxs)
            spacingRow("xs", DS.Spacing.xs)
            spacingRow("sm", DS.Spacing.sm)
            spacingRow("md", DS.Spacing.md)
            spacingRow("lg", DS.Spacing.lg)
            spacingRow("xl", DS.Spacing.xl)
            spacingRow("xxl", DS.Spacing.xxl)
            spacingRow("xxxl", DS.Spacing.xxxl)
            spacingRow("jumbo", DS.Spacing.jumbo)
        }
    }

    private func spacingRow(_ name: String, _ value: CGFloat) -> some View {
        GeometryReader { geo in
            let labelWidth: CGFloat = 50
            let ptLabelWidth: CGFloat = 40
            let maxBarWidth = max(0, geo.size.width - labelWidth - ptLabelWidth - DS.Spacing.md * 2)
            HStack(spacing: DS.Spacing.md) {
                Text(name)
                    .font(DS.Typography.caption)
                    .frame(width: labelWidth, alignment: .trailing)
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(Color.accentColor)
                    .frame(width: min(value * 4, maxBarWidth), height: 16)
                Text("\(Int(value))pt")
                    .font(DS.Typography.micro)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 20)
    }

    // MARK: - Corner Radius

    private var radiusSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Corner Radius")
            HStack(spacing: DS.Spacing.lg) {
                radiusSwatch("xs", DS.Radius.xs)
                radiusSwatch("sm", DS.Radius.sm)
                radiusSwatch("md", DS.Radius.md)
                radiusSwatch("lg", DS.Radius.lg)
                radiusSwatch("xl", DS.Radius.xl)
                radiusSwatch("xxl", DS.Radius.xxl)
            }
        }
    }

    private func radiusSwatch(_ name: String, _ radius: CGFloat) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            RoundedRectangle(cornerRadius: radius)
                .fill(DS.Colors.fillSecondary)
                .frame(width: 44, height: 44)
            Text(name)
                .font(DS.Typography.micro)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Colors

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Colors")

            Text("Semantic").font(DS.Typography.captionBold)
            HStack(spacing: DS.Spacing.md) {
                colorSwatch("Success", DS.Colors.success)
                colorSwatch("Warning", DS.Colors.warning)
                colorSwatch("Error", DS.Colors.error)
                colorSwatch("Info", DS.Colors.info)
            }

            Text("Interactive").font(DS.Typography.captionBold)
            HStack(spacing: DS.Spacing.md) {
                colorSwatch("Going", DS.Colors.going)
                colorSwatch("Interested", DS.Colors.interested)
                colorSwatch("Plan", DS.Colors.plan)
                colorSwatch("Rating", DS.Colors.ratingFill)
            }

            Text("Domain Themes").font(DS.Typography.captionBold)
            HStack(spacing: DS.Spacing.md) {
                colorSwatch("Music", DS.DomainTheme.music.color)
                colorSwatch("Cinema", DS.DomainTheme.cinema.color)
                colorSwatch("Food", DS.DomainTheme.food.color)
                colorSwatch("Comedy", DS.DomainTheme.comedy.color)
            }
            HStack(spacing: DS.Spacing.md) {
                colorSwatch("Theater", DS.DomainTheme.theater.color)
                colorSwatch("Sports", DS.DomainTheme.sports.color)
                colorSwatch("Trivia", DS.DomainTheme.trivia.color)
                colorSwatch("Festival", DS.DomainTheme.festival.color)
            }
        }
    }

    private func colorSwatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
            Text(name)
                .font(DS.Typography.micro)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shadows

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            SectionHeader(title: "Shadows")
            HStack(spacing: DS.Spacing.xl) {
                shadowSwatch("Subtle", DS.Shadow.subtle)
                shadowSwatch("Card Light", DS.Shadow.cardLight)
                shadowSwatch("Card", DS.Shadow.card)
                shadowSwatch("Elevated", DS.Shadow.elevated)
            }
        }
    }

    private func shadowSwatch(_ name: String, _ style: DS.ShadowStyle) -> some View {
        VStack(spacing: DS.Spacing.md) {
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(.background)
                .frame(width: 64, height: 48)
                .dsShadow(style)
            Text(name)
                .font(DS.Typography.micro)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Badges

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Badges & Pills")
            HStack(spacing: DS.Spacing.md) {
                Text("Music").badgeStyle(backgroundColor: DS.DomainTheme.music.color)
                Text("Cinema").badgeStyle(backgroundColor: DS.DomainTheme.cinema.color)
                Text("Today").badgeStyle(backgroundColor: DS.Colors.success)
            }
        }
    }

    // MARK: - Chips

    private var chipSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SectionHeader(title: "Filter Chips")
            HStack(spacing: DS.Spacing.md) {
                Text("All Events").chipStyle(isSelected: true)
                Text("Music").chipStyle(isSelected: false)
                Text("Movies").chipStyle(isSelected: false)
            }
        }
    }

    // MARK: - Glass

    private var glassSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            SectionHeader(title: "Glass Components")

            ZStack {
                LinearGradient(
                    colors: [.indigo, .purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))

                VStack(spacing: DS.Spacing.lg) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text("Glass Card")
                                .font(DS.Typography.heading)
                            Text("Translucent container for rich backgrounds")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: DS.Spacing.lg) {
                        Button("Primary") {}
                            .buttonStyle(.glassPrimary)

                        Button("Secondary") {}
                            .buttonStyle(.glassSecondary)
                    }

                    HStack(spacing: DS.Spacing.lg) {
                        Button {} label: {
                            Image(systemName: "heart")
                        }
                        .buttonStyle(.glassIcon)

                        Button {} label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.glassIcon)

                        Button {} label: {
                            Image(systemName: "bookmark")
                        }
                        .buttonStyle(.glassIcon)
                    }
                }
                .padding(DS.Spacing.xl)
            }
            .frame(height: 320)
            .clipped()
        }
    }
}

#Preview {
    NavigationStack {
        DesignShowcaseView()
    }
}
#endif
