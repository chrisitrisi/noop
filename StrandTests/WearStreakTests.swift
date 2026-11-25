import XCTest
@testable import Strand

/// Pins `WearStreak`: the run of worn days ending today, the grace for a today without data yet, the best
/// run, month/year boundaries and the worn-day predicate.
final class WearStreakTests: XCTestCase {

    func test_counts_the_run_ending_today() {
        let r = WearStreak.compute(wornDays: ["2026-11-14", "2026-11-15", "2026-11-16"], today: "2026-11-16")
        XCTAssertEqual(r, .init(current: 3, best: 3, wornToday: true))
    }

    func test_today_without_data_keeps_the_streak_alive() {
        let r = WearStreak.compute(wornDays: ["2026-11-14", "2026-11-15"], today: "2026-11-16")
        XCTAssertEqual(r.current, 2)
        XCTAssertFalse(r.wornToday)
    }

    func test_a_missed_day_ends_the_streak() {
        let r = WearStreak.compute(wornDays: ["2026-11-10", "2026-11-11", "2026-11-12", "2026-11-14"],
                                   today: "2026-11-16")
        XCTAssertEqual(r.current, 0, "yesterday (the 15th) was not worn")
        XCTAssertEqual(r.best, 3)
    }

    func test_steps_across_month_and_year_boundaries() {
        let r = WearStreak.compute(wornDays: ["2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02"],
                                   today: "2026-01-02")
        XCTAssertEqual(r.current, 4)
        let march = WearStreak.compute(wornDays: ["2026-02-28", "2026-03-01"], today: "2026-03-01")
        XCTAssertEqual(march.current, 2, "2026 has no 29 February")
    }

    func test_steps_across_the_spring_forward_switch() {
        let r = WearStreak.compute(wornDays: ["2026-03-28", "2026-03-29", "2026-03-30"], today: "2026-03-30")
        XCTAssertEqual(r.current, 3)
    }

    func test_malformed_keys_are_ignored() {
        // "2026-11-31" must not roll over into today, the 1st of December
        let r = WearStreak.compute(wornDays: ["2026-11-30", "2026-11-31", "garbage"], today: "2026-12-01")
        XCTAssertEqual(r, .init(current: 1, best: 1, wornToday: false))
    }

    func test_worn_day_predicate() {
        XCTAssertTrue(WearStreak.isWorn(restingHr: 52, strain: nil, totalSleepMin: nil))
        XCTAssertTrue(WearStreak.isWorn(restingHr: nil, strain: 4.2, totalSleepMin: nil))
        XCTAssertTrue(WearStreak.isWorn(restingHr: nil, strain: nil, totalSleepMin: 410))
        XCTAssertFalse(WearStreak.isWorn(restingHr: nil, strain: 0, totalSleepMin: 0))
        XCTAssertFalse(WearStreak.isWorn(restingHr: nil, strain: nil, totalSleepMin: nil))
    }
}
