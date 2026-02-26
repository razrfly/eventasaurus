import SwiftUI

// MARK: - AppTab

enum AppTab: Int, CaseIterable {
    case home, discover, chat

    var label: String {
        switch self {
        case .home: return "My Events"
        case .discover: return "Discover"
        case .chat: return "Chat"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .discover: return "safari"
        case .chat: return "message"
        }
    }
}

// MARK: - GlassTabBar

struct GlassTabBar: View {
    @Binding var selectedTab: AppTab
    var eventCount: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(DS.Spacing.xs)
        .glassBackground(cornerRadius: DS.Radius.full, interactive: false)
        .dsShadow(DS.Shadow.card)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(DS.Animation.standard) { selectedTab = tab }
        } label: {
            VStack(spacing: DS.Spacing.xxs) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 22))
                    if tab == .home && eventCount > 0 {
                        Text(eventCount > 99 ? "99+" : "\(eventCount)")
                            .font(DS.Typography.badge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                            .offset(x: 10, y: -6)
                    }
                }
                Text(tab.label)
                    .font(isSelected ? DS.Typography.captionBold : DS.Typography.caption)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm)
            .background {
                if isSelected {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
