import SwiftUI

/// Consistent section header with optional trailing action or subtitle.
///
/// `subtitle` and `action`+`actionLabel` are mutually exclusive.
/// If both are provided, the action takes precedence and `subtitle` is ignored.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionLabel: String?
    var subtitle: String?

    init(title: String, action: (() -> Void)? = nil, actionLabel: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.action = action
        self.actionLabel = actionLabel
        self.subtitle = subtitle
        assert(
            subtitle == nil || (action == nil && actionLabel == nil),
            "SectionHeader: subtitle and action+actionLabel are mutually exclusive"
        )
        assert(
            (action == nil) == (actionLabel == nil),
            "SectionHeader: action and actionLabel must both be provided or both be nil"
        )
    }

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
