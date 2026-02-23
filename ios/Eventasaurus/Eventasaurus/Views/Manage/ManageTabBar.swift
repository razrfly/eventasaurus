import SwiftUI

/// Tabs available in the event management view.
enum ManageTab: String, CaseIterable, Identifiable, Hashable {
    case overview, guests, polls, insights, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .guests: return "Guests"
        case .polls: return "Polls"
        case .insights: return "Insights"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.text.square"
        case .guests: return "person.2"
        case .polls: return "chart.bar"
        case .insights: return "chart.bar.xaxis"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

/// Scrollable horizontal tab bar for event management.
struct ManageTabBar: View {
    @Binding var selectedTab: ManageTab
    @Namespace private var tabIndicator

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xxl) {
                    ForEach(ManageTab.allCases) { tab in
                        tabButton(tab)
                            .id(tab)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.lg)
            }
            .onChange(of: selectedTab) { _, newTab in
                withAnimation(DS.Animation.fast) {
                    proxy.scrollTo(newTab, anchor: .center)
                }
            }
        }
        .glassBackground(cornerRadius: 0)
    }

    private func tabButton(_ tab: ManageTab) -> some View {
        let isActive = selectedTab == tab

        return Button {
            withAnimation(DS.Animation.fast) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: DS.Spacing.sm) {
                // Icon — large and tappable
                Image(systemName: tab.icon)
                    .font(.title2)
                    .frame(width: 32, height: 32)

                // Label
                Text(tab.title)
                    .font(isActive ? DS.Typography.captionBold : DS.Typography.caption)

                // Animated underline indicator
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2.5)
                        .matchedGeometryEffect(id: "tabIndicator", in: tabIndicator)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2.5)
                }
            }
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .frame(minWidth: 64)
            .contentShape(Rectangle())
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
        .buttonStyle(.plain)
    }
}
