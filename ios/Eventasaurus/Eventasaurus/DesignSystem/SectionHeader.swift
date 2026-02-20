import SwiftUI

/// Consistent section header with optional trailing action.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        HStack {
            Text(title)
                .font(DS.Typography.heading)

            Spacer()

            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .font(DS.Typography.caption)
            }
        }
    }
}

#Preview {
    VStack(spacing: DS.Spacing.xl) {
        SectionHeader(title: "Nearby Events")
        SectionHeader(
            title: "Screenings",
            action: {},
            actionLabel: "See All"
        )
    }
    .padding()
}
