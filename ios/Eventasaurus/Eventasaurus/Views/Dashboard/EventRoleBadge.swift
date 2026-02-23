import SwiftUI

/// Capsule badge showing the user's role for a dashboard event.
struct EventRoleBadge: View {
    let role: DashboardRole

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: icon)
            Text(role.displayName)
        }
        .font(DS.Typography.badge)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private var icon: String {
        switch role {
        case .hosting: return "star.fill"
        case .going: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .notGoing: return "xmark.circle"
        }
    }

    private var color: Color {
        switch role {
        case .hosting: return .green
        case .going: return .blue
        case .pending: return .orange
        case .notGoing: return .red
        }
    }
}
