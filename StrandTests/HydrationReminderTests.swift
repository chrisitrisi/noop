import XCTest
@testable import Strand

/// Pins the water-check pacing: nothing expected before 08:00, the whole goal from 21:00, linear between,
/// and a one-glass slack before it counts as behind.
final class HydrationReminderTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: hour, minute: minute))!
    }

    func testNothingIsExpectedBeforeTheWindowOpens() {
        XCTAssertEqual(HydrationReminder.expectedML(goalML: 2600, now: at(7, 30), calendar: calendar), 0)
        XCTAssertFalse(HydrationReminder.isBehind(totalML: 0, goalML: 2600, now: at(7, 30), calendar: calendar))
    }

    func testHalfwayThroughTheWindowExpectsHalfTheGoal() {
        // 08:00-21:00 is 13 hours, so 14:30 is the midpoint.
        XCTAssertEqual(HydrationReminder.expectedML(goalML: 2600, now: at(14, 30), calendar: calendar),
                       1300, accuracy: 0.5)
    }

    func testTheWholeGoalIsExpectedFromTheEndOfTheWindow() {
        XCTAssertEqual(HydrationReminder.expectedML(goalML: 2600, now: at(21), calendar: calendar), 2600)
        XCTAssertEqual(HydrationReminder.expectedML(goalML: 2600, now: at(23, 30), calendar: calendar), 2600)
    }

    func testOneGlassBehindIsStillOnPace() {
        // 1300 expected at 14:30: 1100 drunk is within the 250 ml slack.
        XCTAssertFalse(HydrationReminder.isBehind(totalML: 1100, goalML: 2600, now: at(14, 30), calendar: calendar))
    }

    func testMoreThanAGlassBehindIsBehind() {
        XCTAssertTrue(HydrationReminder.isBehind(totalML: 900, goalML: 2600, now: at(14, 30), calendar: calendar))
    }

    func testAReachedGoalNeverNudges() {
        XCTAssertFalse(HydrationReminder.isBehind(totalML: 2600, goalML: 2600, now: at(22), calendar: calendar))
    }

    func testNoGoalNeverNudges() {
        XCTAssertFalse(HydrationReminder.isBehind(totalML: 0, goalML: 0, now: at(18), calendar: calendar))
    }
}
