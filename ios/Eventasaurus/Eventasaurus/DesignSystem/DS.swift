import SwiftUI

// MARK: - Eventasaurus Design System
//
// Thin token layer for consistent styling across the app.
// Designed to work with iOS 26 Liquid Glass — no opaque backgrounds
// that would suppress .glassEffect() rendering.

enum DS {

    // MARK: - Spacing (8pt grid)

    enum Spacing {
        /// 2pt — icon-text pairs, fine typography
        static let xxs: CGFloat = 2
        /// 4pt — badge internals, compact elements
        static let xs: CGFloat = 4
        /// 6pt — showtime layouts, tight groupings
        static let sm: CGFloat = 6
        /// 8pt — card content, vertical stacks, filter sections
        static let md: CGFloat = 8
        /// 12pt — subsections, card grids, horizontal layouts
        static let lg: CGFloat = 12
        /// 16pt — main content margins, section spacing
        static let xl: CGFloat = 16
        /// 20pt — form sections
        static let xxl: CGFloat = 20
        /// 24pt — major section gaps
        static let xxxl: CGFloat = 24
        /// 32pt — screen-level vertical padding
        static let jumbo: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        /// 4pt — compact badges, format pills
        static let xs: CGFloat = 4
        /// 6pt — source logos, small thumbnails
        static let sm: CGFloat = 6
        /// 8pt — venue cards, showtime pills
        static let md: CGFloat = 8
        /// 12pt — image containers, posters, map views
        static let lg: CGFloat = 12
        /// 16pt — event cards, primary cards
        static let xl: CGFloat = 16
        /// 20pt — glass panels, modal cards
        static let xxl: CGFloat = 20
        /// 24pt — large glass containers
        static let xxxl: CGFloat = 24
        /// Full rounding — capsule buttons, pills
        static let full: CGFloat = 99
    }

    // MARK: - Typography

    enum Typography {
        /// App name, splash screen
        static let display = Font.largeTitle.bold()
        /// Screen titles, event detail title
        static let title = Font.title2.bold()
        /// Year, rating supplement text
        static let titleSecondary = Font.title3.weight(.semibold)
        /// Section headers (cast, screenings, events)
        static let heading = Font.headline
        /// Dates, venues, descriptions, labels
        static let body = Font.subheadline
        /// Emphasized body text
        static let bodyMedium = Font.subheadline.weight(.medium)
        /// Bold body text (venue names, button labels)
        static let bodyBold = Font.subheadline.bold()
        /// Italic body (taglines)
        static let bodyItalic = Font.subheadline.italic()
        /// Long-form descriptions
        static let prose = Font.body
        /// Secondary text, counts, filters
        static let caption = Font.caption
        /// Emphasized captions
        static let captionBold = Font.caption.bold()
        /// Emphasized captions (medium weight)
        static let captionMedium = Font.caption.weight(.medium)
        /// Badge text, pill labels, minimal text
        static let badge = Font.caption2.weight(.semibold)
        /// Smallest text
        static let micro = Font.caption2
    }

    // MARK: - Shadows

    enum Shadow {
        /// Standard card shadow
        static let card = ShadowStyle(color: .black.opacity(0.08), radius: 8, y: 4)
        /// Lighter shadow for grid items
        static let cardLight = ShadowStyle(color: .black.opacity(0.06), radius: 6, y: 3)
        /// Subtle shadow for floating elements
        static let subtle = ShadowStyle(color: .black.opacity(0.04), radius: 4, y: 2)
        /// Elevated shadow for modals/sheets
        static let elevated = ShadowStyle(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
        var x: CGFloat = 0
    }

    // MARK: - Animation

    enum Animation {
        /// Quick micro-interactions (badge appear, chip select)
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        /// Standard transitions (view changes, content loading)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        /// Smooth page-level transitions
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        /// Spring for interactive elements
        static let spring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        /// Bouncy spring for playful feedback
        static let bouncy = SwiftUI.Animation.bouncy(duration: 0.4)
    }

    // MARK: - Image Sizes

    enum ImageSize {
        /// Hero images on detail views — 220pt
        static let hero: CGFloat = 220
        /// Grid item covers — 200pt
        static let gridCover: CGFloat = 200
        /// Standard card covers — 160pt
        static let cardCover: CGFloat = 160
        /// Source hero sections — 180pt
        static let sourceBanner: CGFloat = 180
        /// Map displays — 160pt
        static let map: CGFloat = 160
        /// Nearby events carousel — 100pt
        static let carouselItem: CGFloat = 100
        /// Profile/cast avatars (large) — 80pt
        static let avatarLarge: CGFloat = 80
        /// Source logos — 56pt
        static let logoLarge: CGFloat = 56
        /// Inline attribution logos — 28pt
        static let logoSmall: CGFloat = 28
    }

    // MARK: - Glass
    //
    // Use the .glassBackground() and .clearGlassBackground() view modifiers
    // from ViewModifiers.swift instead of referencing glass types directly.
    // Glass is for overlay/navigation layers only — never for content rows.

    // MARK: - Domain Colors

    /// Source domain-based theme colors (music venues, cinemas, etc.)
    enum DomainTheme {
        case music, cinema, food, comedy, theater, sports, trivia, festival, other

        var color: Color {
            switch self {
            case .music: .blue
            case .cinema: .indigo
            case .food: .orange
            case .comedy: .yellow
            case .theater: .red
            case .sports: .green
            case .trivia: .purple
            case .festival: .pink
            case .other: .gray
            }
        }

        var gradient: LinearGradient {
            LinearGradient(
                colors: [color.opacity(0.7), color.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
