import Foundation
import StrandAnalytics
import WhoopProtocol

// MARK: - WorkoutZoneGuard
//
// Zone training for a manual workout: the wearer picks a target HR zone ("hold Zone 2") when the workout
// starts, and the strap buzzes when the heart rate stays out of it. The decision is the pure
// `LiveSessionEngine` with a user-set `TargetBand` (dwell, cool-down, hysteresis and warm-up silence all
// carry over); this object only feeds it the workout's live samples and walks a cue out to the wrist.
//
//   • below the zone → the Live Session "push" signal (two short pulses)
//   • above the zone → the Live Session "ease off" signal (three long pulses)
//
// The target survives an OS kill with the workout itself: it is stored next to the workout snapshot and
// re-armed on rehydrate. It holds one realtime-HR arm while guarding (a WHOOP 5/MG only streams live HR
// while armed, #681), balanced by `stop()`.

/// UserDefaults keys for the zone a running workout guards.
enum WorkoutZonePrefs {
    static let targetZone = "noop.workoutTargetZone"
    static let warmupSec = "noop.workoutTargetZoneWarmupSec"
}

@MainActor
final class WorkoutZoneGuard: ObservableObject {

    /// The zone being held (1...5), nil when the workout has no target.
    @Published private(set) var targetZone: Int?
    /// The engine's latest verdict, for the live workout card.
    @Published private(set) var output: LiveSessionEngine.Output?

    private var engine: LiveSessionEngine?
    private weak var model: AppModel?
    private var hapticWalkUntil = Date.distantPast

    /// Arm the guard for `zone` of `zones`. `warmupSec` keeps the first part of the workout cue-free
    /// (a run that starts with a walk). Re-arming replaces a running target.
    func start(zone: Int, zones: HRZoneSet, restingHR: Double, warmupSec: Int,
               model: AppModel, startedAt: Date) {
        guard let band = zones.zones.first(where: { $0.number == zone }) else { return }
        if engine == nil { model.startRealtimeHR() }
        self.model = model
        let config = LiveSessionEngine.Config(
            restingHR: restingHR, hrMax: zones.maxHR, charge: nil,
            targetBand: .init(floorBpm: band.lower, ceilingBpm: band.upper),
            warmupSec: max(warmupSec, 0))
        engine = LiveSessionEngine(config: config, startTs: Int(startedAt.timeIntervalSince1970))
        targetZone = zone
        output = nil
        UserDefaults.standard.set(zone, forKey: WorkoutZonePrefs.targetZone)
        UserDefaults.standard.set(warmupSec, forKey: WorkoutZonePrefs.warmupSec)
    }

    /// Feed one live sample of the running workout. A no-op without a target.
    func feed(bpm: Int, at date: Date = Date()) {
        guard var engine else { return }
        let out = engine.update(now: Int(date.timeIntervalSince1970), bpm: bpm)
        self.engine = engine
        output = out
        if let cue = out.cue { fire(cue) }
    }

    /// Stop guarding and release the realtime-HR arm. Safe to call when nothing is guarded.
    func stop() {
        UserDefaults.standard.removeObject(forKey: WorkoutZonePrefs.targetZone)
        UserDefaults.standard.removeObject(forKey: WorkoutZonePrefs.warmupSec)
        guard engine != nil else { return }
        engine = nil
        targetZone = nil
        output = nil
        model?.stopRealtimeHR()
        model = nil
    }

    /// The target stored for a workout that was running when the app was killed, if any.
    static func storedTarget() -> (zone: Int, warmupSec: Int)? {
        let d = UserDefaults.standard
        guard let zone = d.object(forKey: WorkoutZonePrefs.targetZone) as? Int else { return nil }
        return (zone, d.integer(forKey: WorkoutZonePrefs.warmupSec))
    }

    /// Walk a cue's pulses out through the strap, the same way `LiveSessionRunner` does. Drop-tolerant: a
    /// cue arriving while the previous walk is still buzzing is skipped, a late buzz is a wrong buzz.
    private func fire(_ cue: LiveSessionEngine.Cue) {
        let now = Date()
        guard now >= hapticWalkUntil, let ble = model?.ble,
              HapticPrefs.enabled(HapticPrefs.workout) else { return }
        let signal: LiveSessionHaptics.Signal = (cue == .pushNudge) ? .push : .easeOff
        var offsetMs = 0
        for pulse in LiveSessionHaptics.pulses(for: signal) {
            let loops = pulse.isLong ? 2 : 1
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(offsetMs)) { [weak ble] in
                ble?.send(.runHapticsPattern, payload: [2, UInt8(clamping: loops), 0, 0, 0])
            }
            offsetMs += pulse.durationMs + pulse.gapMs
        }
        hapticWalkUntil = now.addingTimeInterval(Double(offsetMs) / 1000)
    }
}
