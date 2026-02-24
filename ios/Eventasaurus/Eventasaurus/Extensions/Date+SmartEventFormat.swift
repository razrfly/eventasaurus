import Foundation

extension Date {
    /// Smart event date formatting that adapts based on proximity:
    /// - Today → "Today, 5:30 PM"
    /// - Tomorrow → "Tomorrow, 7:00 PM"
    /// - Within 6 days → "Wed, 5:30 PM"
    /// - Beyond → "28 Feb, 5:30 PM"
    ///
    /// Respects the user's locale for 12h/24h time formatting.
    func smartEventFormat() -> String {
        let calendar = Calendar.current
        let time = self.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(self) {
            return String(localized: "Today, \(time)")
        }

        if calendar.isDateInTomorrow(self) {
            return String(localized: "Tomorrow, \(time)")
        }

        let daysAway = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: self)).day ?? 7

        if daysAway >= 2 && daysAway <= 6 {
            let weekday = self.formatted(.dateTime.weekday(.abbreviated))
            return "\(weekday), \(time)"
        }

        let dayMonth = self.formatted(.dateTime.day().month(.abbreviated))
        return "\(dayMonth), \(time)"
    }
}
