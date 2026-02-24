import Foundation

extension Date {
    /// Smart event date formatting that adapts based on proximity:
    /// - Today → "5:30 PM" (day shown via badge elsewhere)
    /// - Tomorrow → "5:30 PM" (day shown via badge elsewhere)
    /// - Within 6 days → "Wed, 5:30 PM"
    /// - Beyond → "28 Feb, 5:30 PM"
    ///
    /// Today/tomorrow omit the day prefix because the trailing badge already
    /// communicates which day it is — avoids wrapping on compact rows.
    /// Respects the user's locale for 12h/24h time formatting.
    func smartEventFormat() -> String {
        let calendar = Calendar.current
        let time = self.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(self) || calendar.isDateInTomorrow(self) {
            return time
        }

        let daysAway = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: self)).day ?? 7

        if daysAway >= 2 && daysAway <= 6 {
            let weekday = self.formatted(.dateTime.weekday(.abbreviated))
            return String(localized: "\(weekday), \(time)")
        }

        let dayMonth = self.formatted(.dateTime.day().month(.abbreviated))
        return String(localized: "\(dayMonth), \(time)")
    }
}
