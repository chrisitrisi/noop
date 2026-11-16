#if os(iOS)
import Foundation
import AppIntents

// Shortcuts actions that start and end a manual workout, optionally holding a heart-rate zone
// (`WorkoutZoneGuard`): "Start Workout: Running, Zone 2" turns the strap into a zone-2 coach that
// buzzes when the heart rate stays out of the zone. Meant to be chained with another app's actions,
// e.g. a gym app's "start workout" followed by this one.

/// The sports offered in Shortcuts. The raw value is the stored NOOP sport label (`WorkoutCatalog`
/// names are data, never localised); `sauna` is a free-text label outside the catalogue, written to
/// Apple Health as a Mind and Body workout (see `HealthKitBridge.activityType(forSport:)`).
enum WorkoutSportChoice: String, AppEnum, CaseIterable {
    case running = "Running"
    case walking = "Walking"
    case cycling = "Cycling"
    case treadmillRun = "Treadmill run"
    case strength = "Strength"
    case sauna = "Sauna"
    case other = "Other"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sport")

    static var caseDisplayRepresentations: [WorkoutSportChoice: DisplayRepresentation] = [
        .running: DisplayRepresentation(title: "Running"),
        .walking: DisplayRepresentation(title: "Walking"),
        .cycling: DisplayRepresentation(title: "Cycling"),
        .treadmillRun: DisplayRepresentation(title: "Treadmill run"),
        .strength: DisplayRepresentation(title: "Strength"),
        .sauna: DisplayRepresentation(title: "Sauna"),
        .other: DisplayRepresentation(title: "Other"),
    ]
}

/// The zone a workout should hold. `none` starts a plain workout.
enum TargetZoneChoice: Int, AppEnum, CaseIterable {
    case none = 0
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Target Zone")

    static var caseDisplayRepresentations: [TargetZoneChoice: DisplayRepresentation] = [
        .none: DisplayRepresentation(title: "No target"),
        .zone1: DisplayRepresentation(title: "Zone 1"),
        .zone2: DisplayRepresentation(title: "Zone 2"),
        .zone3: DisplayRepresentation(title: "Zone 3"),
        .zone4: DisplayRepresentation(title: "Zone 4"),
        .zone5: DisplayRepresentation(title: "Zone 5"),
    ]
}

/// Waits briefly for the app model: a Shortcut can hand an intent its first tick before a cold launch
/// has built it.
@MainActor
private func waitForAppModel(seconds: Int = 5) async -> AppModel? {
    for _ in 0..<(seconds * 4) {
        if let model = AppModel.shared { return model }
        try? await Task.sleep(nanoseconds: 250_000_000)
    }
    return AppModel.shared
}

/// Start a manual workout, optionally holding a heart-rate zone. Opens NOOP: GPS route recording and
/// the live strap link want the app in front when the session begins.
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workout"
    static var description = IntentDescription(
        "Start a workout in NOOP. With a target zone, the strap buzzes when your heart rate stays below it (two short pulses) or above it (three long pulses).")
    static var openAppWhenRun = true

    @Parameter(title: "Sport", default: .running)
    var sport: WorkoutSportChoice

    @Parameter(title: "Target Zone", default: .none)
    var zone: TargetZoneChoice

    /// Minutes without buzzes at the start, e.g. the walk before a run.
    @Parameter(title: "Warm-up (minutes)", default: 0, inclusiveRange: (0, 30))
    var warmupMinutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$sport) workout holding \(\.$zone)") {
            \.$warmupMinutes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = await waitForAppModel() else {
            return .result(dialog: "NOOP isn't ready yet. Open NOOP and try again.")
        }
        guard model.activeWorkout == nil else {
            return .result(dialog: "A workout is already running in NOOP.")
        }
        let targetZone = zone == .none ? nil : zone.rawValue
        model.startWorkout(sport: sport.rawValue, targetZone: targetZone,
                           zoneWarmupSec: max(warmupMinutes, 0) * 60)
        if let targetZone {
            return .result(dialog: "\(sport.rawValue) started, holding Zone \(targetZone).")
        }
        return .result(dialog: "\(sport.rawValue) started.")
    }
}

/// End and save the running workout without opening NOOP. NOOP writes it to Apple Health with its next
/// Health write-back, like a workout ended in the app.
struct EndWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "End Workout"
    static var description = IntentDescription("End and save the workout running in NOOP.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = await waitForAppModel(), let workout = model.activeWorkout else {
            return .result(dialog: "No workout is running in NOOP.")
        }
        let tooShort = AppModel.isTooShortToSave(elapsedSeconds: workout.elapsed(at: Date()))
        model.endWorkout()
        if tooShort {
            return .result(dialog: "The workout was shorter than a minute, so NOOP didn't save it.")
        }
        return .result(dialog: "\(workout.sport) saved.")
    }
}
#endif
