import SwiftUI

/// A form row with a native SwiftUI DatePicker that enforces 30-minute intervals.
/// Uses snap-on-change since SwiftUI DatePicker doesn't support minuteInterval natively.
struct DatePicker30MinRow: View {
    let label: String
    @Binding var selection: Date
    var minimumDate: Date?

    /// Tracks whether we're programmatically snapping to avoid infinite loops
    @State private var isSnapping = false

    var body: some View {
        Group {
            if let minimumDate {
                DatePicker(label, selection: $selection, in: minimumDate..., displayedComponents: [.date, .hourAndMinute])
            } else {
                DatePicker(label, selection: $selection, displayedComponents: [.date, .hourAndMinute])
            }
        }
        .onChange(of: selection) {
            guard !isSnapping else { return }
            let snapped = selection.snappedToNearest30Minutes()
            if abs(snapped.timeIntervalSince(selection)) > 1 {
                isSnapping = true
                selection = snapped
                isSnapping = false
            }
        }
    }
}
