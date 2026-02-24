import SwiftUI

/// Toolbar button that cycles through `EventViewMode` states (compact → card → grid → compact).
/// Optionally persists the mode to UserDefaults.
struct ViewModeToggle: View {
    @Binding var mode: EventViewMode
    var persistKey: String? = nil

    var body: some View {
        Button {
            withAnimation(DS.Animation.fast) {
                mode = mode.next
            }
            if let persistKey {
                mode.save(key: persistKey)
            }
        } label: {
            Image(systemName: mode.next.icon)
        }
        .accessibilityLabel("Switch to \(mode.next.rawValue) view")
    }
}
