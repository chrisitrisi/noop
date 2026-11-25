import Foundation

// WearStreak.swift — consecutive days the strap was worn. Pure, deterministic, DB-free. App-layer
// (Apple only): the Android app has no streak card.
//
// A day counts as worn when the strap produced a day of its own: an Effort, a resting heart rate or a
// banked night. The streak is the run of worn days ending today, or ending yesterday while today has no
// data yet (the day is not over, so an unworn-so-far today does not break it). Days are the store's
// "YYYY-MM-DD" keys and are stepped on a fixed UTC Gregorian calendar, so a DST switch cannot make a
// day vanish or repeat.
enum WearStreak {

    struct Result: Equatable, Sendable {
        /// Worn days in a row up to today (or yesterday, while today has no data yet).
        let current: Int
        /// The longest run in the given days.
        let best: Int
        /// Whether today already counts. False means the streak is still alive but needs today's wear.
        let wornToday: Bool
        init(current: Int, best: Int, wornToday: Bool) {
            self.current = current; self.best = best; self.wornToday = wornToday
        }
    }

    /// Whether a day's metrics show the strap was worn.
    static func isWorn(restingHr: Int?, strain: Double?, totalSleepMin: Double?) -> Bool {
        restingHr != nil || (strain ?? 0) > 0 || (totalSleepMin ?? 0) > 0
    }

    /// The streak over `wornDays` ("YYYY-MM-DD" keys) as of `today`. Malformed keys are ignored.
    static func compute(wornDays: Set<String>, today: String) -> Result {
        let days = Set(wornDays.compactMap(dayNumber))
        guard let todayNumber = dayNumber(today) else { return Result(current: 0, best: 0, wornToday: false) }

        let wornToday = days.contains(todayNumber)
        var current = 0
        var cursor = wornToday ? todayNumber : todayNumber - 1
        while days.contains(cursor) {
            current += 1
            cursor -= 1
        }

        var best = 0
        for day in days where !days.contains(day - 1) {
            var length = 1
            while days.contains(day + length) { length += 1 }
            best = max(best, length)
        }
        return Result(current: current, best: best, wornToday: wornToday)
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let epoch = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!

    /// Days since 2000-01-01 for a "YYYY-MM-DD" key, nil when it is not one.
    private static func dayNumber(_ key: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d),
              let date = calendar.date(from: DateComponents(year: y, month: m, day: d)),
              calendar.component(.day, from: date) == d else { return nil }
        return calendar.dateComponents([.day], from: epoch, to: date).day
    }
}
