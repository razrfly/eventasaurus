#if DEBUG
import SwiftUI

/// Shared environment indicator used on the sign-in screen and profile page.
/// Shows the current environment name, an optional subtitle, and a restart-pending
/// cue when `DevEnvironmentService.shared.needsRestart` is true.
struct EnvironmentBadge: View {
    var subtitle: String?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Circle()
                .fill(AppConfig.useProductionServer ? .red : .green)
                .frame(width: 8, height: 8)

            Text(AppConfig.environmentName)
                .font(DS.Typography.captionBold)

            if DevEnvironmentService.shared.needsRestart {
                Text("·")
                    .foregroundStyle(.orange)
                Text("Restart required")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.orange)
            } else if let subtitle {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
