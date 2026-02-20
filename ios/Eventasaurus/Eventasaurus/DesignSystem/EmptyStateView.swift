import SwiftUI

/// Consistent empty state with icon, title, message, and optional action.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
                .font(DS.Typography.title)
        } description: {
            Text(message)
                .font(DS.Typography.body)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    EmptyStateView(
        icon: "calendar.badge.exclamationmark",
        title: "No Events Found",
        message: "Try adjusting your filters or searching in a different city.",
        actionTitle: "Clear Filters",
        action: {}
    )
}
