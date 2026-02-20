import SwiftUI

/// Consistent section header with optional trailing action or subtitle.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionLabel: String?
    var subtitle: String?

    var body: some View {
        HStack {
            Text(title)
                .font(DS.Typography.heading)

            Spacer()

            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .font(DS.Typography.caption)
            } else if let subtitle {
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
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
