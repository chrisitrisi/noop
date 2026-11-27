import XCTest
@testable import Strand

/// Pins the once-a-day rule of the wear-streak splash: shown at most once per logical day, never for a
/// streak of zero, never when switched off.
final class WearStreakSplashTests: XCTestCase {
    func testDueOnTheFirstOpenOfADayWithAStreak() {
        XCTAssertTrue(WearStreakSplashPrefs.isDue(enabled: true, current: 12,
                                                  lastShownDay: "2026-11-24", today: "2026-11-25"))
    }

    func testDueOnTheVeryFirstOpenEver() {
        XCTAssertTrue(WearStreakSplashPrefs.isDue(enabled: true, current: 1,
                                                  lastShownDay: "", today: "2026-11-25"))
    }

    func testNotAgainTheSameDay() {
        XCTAssertFalse(WearStreakSplashPrefs.isDue(enabled: true, current: 12,
                                                   lastShownDay: "2026-11-25", today: "2026-11-25"))
    }

    func testNothingToCelebrateWithoutAStreak() {
        XCTAssertFalse(WearStreakSplashPrefs.isDue(enabled: true, current: 0,
                                                   lastShownDay: "2026-11-24", today: "2026-11-25"))
    }

    func testSwitchedOffStaysOff() {
        XCTAssertFalse(WearStreakSplashPrefs.isDue(enabled: false, current: 30,
                                                   lastShownDay: "2026-11-24", today: "2026-11-25"))
    }
}
