import Foundation

/// When the "Water check" shortcut (fork extra) should nudge: the day's goal spread evenly over the waking
/// window, compared with what was drunk so far. Pure, so the pacing rule is unit-tested; the intent only
/// supplies the day total, the goal and the clock.
enum HydrationReminder {
    /// The window the goal is spread over, in local hours. Before it nothing is expected yet; after it the
    /// whole goal is.
    static let startHour = 8
    static let endHour = 21
    /// How far behind the pace counts as behind. One glass, so a reminder never fires over a sip.
    static let slackML = 250.0

    /// Millilitres the pace expects by `now`: 0 before `startHour`, the full goal from `endHour`, linear in
    /// between.
    static func expectedML(goalML: Int, now: Date, calendar: Calendar = .current) -> Double {
        guard goalML > 0 else { return 0 }
        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: now) ?? now
        let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: now) ?? now
        guard now > start else { return 0 }
        guard now < end else { return Double(goalML) }
        let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return Double(goalML) * fraction
    }

    /// Behind when the day total trails the pace by more than `slackML` and the goal is not reached yet.
    static func isBehind(totalML: Double, goalML: Int, now: Date, calendar: Calendar = .current) -> Bool {
        guard goalML > 0, totalML < Double(goalML) else { return false }
        return totalML + slackML < expectedML(goalML: goalML, now: now, calendar: calendar)
    }
}
