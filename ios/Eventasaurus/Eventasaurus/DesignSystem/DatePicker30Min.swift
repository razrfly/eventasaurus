import SwiftUI

/// A pair of form rows for selecting date and time with 30-minute intervals.
/// Row 1: Native SwiftUI DatePicker for the date portion.
/// Row 2: SwiftUI Picker with exactly 48 half-hour time slots (matching web parity).
struct DatePicker30MinRow: View {
    let label: String
    @Binding var selection: Date
    var minimumDate: Date?

    /// Current time as minutes-since-midnight, snapped to nearest 30
    private var selectedSlot: Int {
        let cal = Calendar.current
        let h = cal.component(.hour, from: selection)
        let m = cal.component(.minute, from: selection)
        let total = h * 60 + m
        let snapped = ((total + 15) / 30) * 30
        return snapped >= 1440 ? 0 : snapped
    }

    /// All 48 half-hour slots: 0, 30, 60, 90, ... 1410
    private static let timeSlots: [Int] = Array(stride(from: 0, to: 1440, by: 30))

    var body: some View {
        // Date row — native SwiftUI compact date picker
        Group {
            if let minimumDate {
                DatePicker(label, selection: $selection, in: minimumDate..., displayedComponents: .date)
            } else {
                DatePicker(label, selection: $selection, displayedComponents: .date)
            }
        }

        // Time row — Picker with 48 discrete half-hour slots
        Picker("Time", selection: Binding(
            get: { selectedSlot },
            set: { newSlot in
                let cal = Calendar.current
                var comps = cal.dateComponents([.year, .month, .day], from: selection)
                comps.hour = newSlot / 60
                comps.minute = newSlot % 60
                if let newDate = cal.date(from: comps) {
                    selection = newDate
                }
            }
        )) {
            ForEach(Self.timeSlots, id: \.self) { minutes in
                Text(Self.formatTime(minutes: minutes))
                    .tag(minutes)
            }
        }
    }

    private static func formatTime(minutes: Int) -> String {
        let comps = DateComponents(hour: minutes / 60, minute: minutes % 60)
        guard let date = Calendar.current.date(from: comps) else { return "" }
        return date.formatted(.dateTime.hour().minute())
    }
}
