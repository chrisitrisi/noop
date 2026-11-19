import XCTest
@testable import Strand

/// Pins the bedtime-caffeine arithmetic behind the Today "Drinks & caffeine" card and the shape of its
/// presets. Dates are built in a fixed time zone so the evening/midnight boundaries are the same on
/// every machine.
final class IntakePresetsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: upcomingBedtime

    func testBedtimeLaterTodayIsThisEvening() {
        let bedtime = CaffeineAtBedtime.upcomingBedtime(now: at(19, 15), bedtimeMinutes: 23 * 60,
                                                        calendar: calendar)
        XCTAssertEqual(bedtime, at(19, 23))
    }

    func testBedtimeAlreadyPassedTonightGivesNothing() {
        XCTAssertNil(CaffeineAtBedtime.upcomingBedtime(now: at(19, 23, 30), bedtimeMinutes: 23 * 60,
                                                       calendar: calendar))
    }

    func testAfterMidnightBedtimeBelongsToTheComingNight() {
        // 00:30 bedtime, read at 21:00: the bedtime is in 3.5 hours, not 20.5 hours ago.
        let bedtime = CaffeineAtBedtime.upcomingBedtime(now: at(19, 21), bedtimeMinutes: 30,
                                                        calendar: calendar)
        XCTAssertEqual(bedtime, at(20, 0, 30))
    }

    func testAfterMidnightBedtimeStillAheadInTheSmallHours() {
        // 00:30 bedtime read at 00:10: still tonight's, 20 minutes away.
        let bedtime = CaffeineAtBedtime.upcomingBedtime(now: at(20, 0, 10), bedtimeMinutes: 30,
                                                        calendar: calendar)
        XCTAssertEqual(bedtime, at(20, 0, 30))
    }

    // MARK: remainingMg

    func testOneHalfLifeBeforeBedtimeLeavesHalf() {
        let half = CaffeineDecay.defaultHalfLifeHours
        let bedtime = at(19, 23)
        let intake = CaffeineIntake(at: bedtime.addingTimeInterval(-half * 3600), mg: 100)
        let mg = CaffeineAtBedtime.remainingMg(intakes: [intake], now: at(19, 18), bedtime: bedtime)
        XCTAssertEqual(mg!, 50, accuracy: 0.01)
    }

    func testIntakesAreSummedAndUnknownAmountsSkipped() {
        let bedtime = at(19, 23)
        let intakes = [
            CaffeineIntake(at: at(19, 23), mg: 80),          // logged right at bedtime: all of it remains
            CaffeineIntake(at: at(19, 22), mg: nil),         // no amount: contributes nothing
        ]
        let mg = CaffeineAtBedtime.remainingMg(intakes: intakes, now: at(19, 23), bedtime: bedtime)
        XCTAssertEqual(mg!, 80, accuracy: 0.01)
    }

    func testNoAmountAnywhereGivesNoNumber() {
        let intakes = [CaffeineIntake(at: at(19, 9), mg: nil)]
        XCTAssertNil(CaffeineAtBedtime.remainingMg(intakes: intakes, now: at(19, 10), bedtime: at(19, 23)))
    }

    func testFutureDatedIntakeIsIgnored() {
        let intakes = [CaffeineIntake(at: at(19, 20), mg: 100)]
        let mg = CaffeineAtBedtime.remainingMg(intakes: intakes, now: at(19, 10), bedtime: at(19, 23))
        XCTAssertNil(mg)
    }

    // MARK: presets

    func testPresetIdsAreUniqueAcrossButtonsAndChips() {
        let ids = (IntakePreset.primaryWater + IntakePreset.chips).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testPrimaryWaterButtonsAreQuarterAndHalfLitre() {
        XCTAssertEqual(IntakePreset.primaryWater.map(\.kind), [.water(ml: 250), .water(ml: 500)])
    }

    func testEveryCaffeinePresetHasATranslatedNameAndAPositiveDose() {
        for preset in IntakePreset.chips {
            guard case .caffeine(let mg) = preset.kind else { continue }
            XCTAssertGreaterThan(mg, 0, preset.id)
            // An unmapped id falls through to the raw id, which would show "coffeeSmall" on the chip.
            XCTAssertNotEqual(preset.title, preset.id, "\(preset.id) has no display name")
        }
    }
}
