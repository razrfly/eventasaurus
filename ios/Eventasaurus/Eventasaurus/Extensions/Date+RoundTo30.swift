import Foundation

extension Date {
    /// Rounds up to the next 30-minute boundary.
    /// Used for create-event defaults (e.g., 2:07 -> 2:30, 2:31 -> 3:00).
    func roundedUpToNext30Minutes() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        guard let minute = components.minute else { return self }

        let nextMinute: Int
        if minute == 0 || minute == 30 {
            nextMinute = minute
        } else if minute < 30 {
            nextMinute = 30
        } else {
            nextMinute = 60
        }

        let minutesToAdd = nextMinute - minute
        guard let rounded = calendar.date(byAdding: .minute, value: minutesToAdd, to: self) else {
            return self
        }

        // Zero out seconds
        let clean = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rounded)
        return calendar.date(from: clean) ?? rounded
    }

    /// Snaps to the nearest 30-minute slot.
    /// Used for edit view to normalize existing event times (e.g., 10:14 -> 10:00, 10:16 -> 10:30).
    func snappedToNearest30Minutes() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        guard let minute = components.minute else { return self }

        let snapped: Int
        if minute < 15 {
            snapped = 0
        } else if minute < 45 {
            snapped = 30
        } else {
            snapped = 60
        }

        let minutesToAdd = snapped - minute
        guard let rounded = calendar.date(byAdding: .minute, value: minutesToAdd, to: self) else {
            return self
        }

        let clean = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rounded)
        return calendar.date(from: clean) ?? rounded
    }
}
