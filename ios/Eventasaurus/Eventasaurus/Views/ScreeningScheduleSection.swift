import SwiftUI

/// Screening schedule for a movie screening event — shows day picker tabs and
/// showtimes grouped by date, matching the web's "Daily Shows Available" section.
/// Used on EventDetailView for events that have occurrences data.
struct ScreeningScheduleSection: View {
    let showtimes: [EventShowtime]
    let venueName: String?
    @State private var selectedDate: String?

    private var showtimesByDate: [(String, [EventShowtime])] {
        let grouped = Dictionary(grouping: showtimes, by: \.date)
        return grouped.sorted { $0.key < $1.key }
    }

    private var upcomingDates: [(String, [EventShowtime])] {
        showtimesByDate.filter { _, times in
            times.contains(where: \.isUpcoming)
        }
    }

    private var activeDate: String? {
        selectedDate ?? upcomingDates.first?.0 ?? showtimesByDate.first?.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            // Header
            Label("Screening Schedule", systemImage: "film.stack")
                .font(DS.Typography.heading)

            // Date range + count
            if let first = showtimesByDate.first?.0, let last = showtimesByDate.last?.0 {
                let upcoming = showtimes.filter(\.isUpcoming)
                Text("\(upcoming.count) show\(upcoming.count == 1 ? "" : "s") from \(formatDate(first)) to \(formatDate(last))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            // Day picker tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.md) {
                    ForEach(showtimesByDate, id: \.0) { date, times in
                        let upcomingCount = times.filter(\.isUpcoming).count
                        Button {
                            withAnimation(DS.Animation.fast) {
                                selectedDate = date
                            }
                        } label: {
                            let isSelected = activeDate == date
                            VStack(spacing: DS.Spacing.xxs) {
                                Text(dayLabel(date))
                                    .font(DS.Typography.captionBold)
                                Text("\(upcomingCount) show\(upcomingCount == 1 ? "" : "s")")
                                    .font(DS.Typography.micro)
                                    .foregroundStyle(isSelected ? .white : .secondary)
                            }
                            .glassChipStyle(isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Venue name
            if let venueName {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(venueName)
                        .font(DS.Typography.bodyBold)
                }
            }

            // Showtimes for selected date
            if let activeDate, let times = showtimesByDate.first(where: { $0.0 == activeDate })?.1 {
                let byFormat = groupByFormat(times)
                ForEach(byFormat, id: \.0) { format, formatTimes in
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        if let format {
                            Text(format)
                                .font(DS.Typography.captionBold)
                        }

                        FlowLayout(spacing: DS.Spacing.sm) {
                            ForEach(formatTimes) { showtime in
                                screeningPill(showtime)
                            }
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.xl)
        .glassBackground(cornerRadius: DS.Radius.xl)
    }

    // MARK: - Screening Pill

    private func screeningPill(_ showtime: EventShowtime) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            if let datetime = showtime.datetime {
                Text(datetime, format: .dateTime.hour().minute())
                    .font(DS.Typography.bodyBold)
            } else if let time = showtime.time {
                Text(time)
                    .font(DS.Typography.bodyBold)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .glassBackground(cornerRadius: DS.Radius.md, interactive: showtime.isUpcoming)
        .opacity(showtime.isUpcoming ? 1.0 : 0.5)
    }

    // MARK: - Helpers

    private func groupByFormat(_ times: [EventShowtime]) -> [(String?, [EventShowtime])] {
        let grouped = Dictionary(grouping: times, by: \.format)
        // Put nil format last
        return grouped.sorted { ($0.key ?? "zzz") < ($1.key ?? "zzz") }
    }

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d")
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM d, yyyy")
        return f
    }()

    private func dayLabel(_ isoDate: String) -> String {
        guard let date = DS.DateFormatting.isoDate.date(from: isoDate) else { return isoDate }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return Self.dayLabelFormatter.string(from: date)
    }

    private func formatDate(_ isoDate: String) -> String {
        guard let date = DS.DateFormatting.isoDate.date(from: isoDate) else { return isoDate }
        return Self.displayDateFormatter.string(from: date)
    }
}
