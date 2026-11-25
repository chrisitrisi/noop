import XCTest
@testable import Strand

/// Pins the `noop://workout/...` links the downloadable shortcuts open.
final class WorkoutLinkTests: XCTestCase {

    private func parse(_ s: String) -> WorkoutLink? { WorkoutLink.parse(URL(string: s)!) }

    func test_start_with_sport_zone_and_warmup() {
        XCTAssertEqual(parse("noop://workout/start?sport=Running&zone=2&warmup=5"),
                       .start(sport: "Running", zone: 2, warmupSec: 300))
    }

    func test_start_decodes_a_sport_with_spaces() {
        XCTAssertEqual(parse("noop://workout/start?sport=Treadmill%20run"),
                       .start(sport: "Treadmill run", zone: nil, warmupSec: 0))
    }

    func test_start_without_sport_is_other_and_bad_values_are_dropped() {
        XCTAssertEqual(parse("noop://workout/start?zone=9&warmup=-3"),
                       .start(sport: WorkoutCatalog.defaultSportName, zone: nil, warmupSec: 0))
        XCTAssertEqual(parse("noop://workout/start?warmup=90"),
                       .start(sport: WorkoutCatalog.defaultSportName, zone: nil, warmupSec: 1800))
    }

    func test_end() {
        XCTAssertEqual(parse("noop://workout/end"), .end)
    }

    func test_other_links_are_not_workout_links() {
        XCTAssertNil(parse("noop://import-health?data=x"))
        XCTAssertNil(parse("noop://workout/pause"))
        XCTAssertNil(parse("wger://workout/start"))
    }
}
