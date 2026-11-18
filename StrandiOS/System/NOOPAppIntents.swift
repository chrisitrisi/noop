#if os(iOS)
import Foundation
import AppIntents
import WhoopProtocol

/// Queue of actions requested by an App Intent while the app may be suspended. Intents can't reach
/// into the running `AppModel` directly (BLE only lives in the foreground app), so they enqueue here
/// and the app drains the queue when it next becomes active.
enum PendingIntents {
    enum Action: String { case markMoment, buzz, askCoach }

    private static let key = "noop.pendingIntents"
    /// K9: the question text for a pending `.askCoach` action. Stored separately because the
    /// action queue encodes as `[String]` and a question can contain colons.
    private static let coachQuestionKey = "noop.pendingCoachQuestion"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.suiteName) }

    /// Optional `at` is the invocation time, captured now and consumed on drain. Encoded into the
    /// stored string as "rawValue:epochSeconds" so the array stays a plain [String] (no schema
    /// migration; a legacy bare "markMoment" still decodes with a nil date).
    static func append(_ action: Action, at date: Date? = nil) {
        guard let d = defaults else { return }
        var list = d.stringArray(forKey: key) ?? []
        if let date { list.append("\(action.rawValue):\(date.timeIntervalSince1970)") }
        else { list.append(action.rawValue) }
        d.set(list, forKey: key)
    }

    /// K9: queue an "Ask Coach" action with the associated question text. The question is stored
    /// in a dedicated key (one pending question at a time — the user rarely queues multiple Siri
    /// questions before the app opens).
    static func appendAskCoach(question: String, at date: Date? = nil) {
        guard let d = defaults else { return }
        d.set(question, forKey: coachQuestionKey)
        append(.askCoach, at: date)
    }

    /// K9: read and clear the pending coach question. Returns nil when no question is queued.
    static func consumeCoachQuestion() -> String? {
        guard let d = defaults else { return nil }
        let q = d.string(forKey: coachQuestionKey)
        d.removeObject(forKey: coachQuestionKey)
        return q
    }

    static func drain() -> [(action: Action, date: Date?)] {
        guard let d = defaults else { return [] }
        let raw = d.stringArray(forKey: key) ?? []
        d.removeObject(forKey: key)
        return raw.compactMap { entry in
            // Guard `parts.first` rather than subscripting `parts[0]`: split(omittingEmptySubsequences:
            // true by default) returns an EMPTY array for an empty or ":"-leading entry, and indexing
            // [0] there is a fatal trap. This value comes from shared App Group defaults read untrusted,
            // so a corrupt/foreign entry must be skipped, not crash the app on foreground.
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let first = parts.first, let action = Action(rawValue: String(first)) else { return nil }
            let date = parts.count == 2 ? Double(parts[1]).map { Date(timeIntervalSince1970: $0) } : nil
            return (action, date)
        }
    }
}

/// Record a timestamped "moment" — the iOS analogue of the strap double-tap "mark a moment" action.
struct MarkMomentIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark a Moment"
    static var description = IntentDescription("Record a timestamped moment in NOOP.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingIntents.append(.markMoment, at: Date())
        return .result(dialog: "Moment marked.")
    }
}

/// Why a background shortcut could not do its job. Shown by Shortcuts / Siri as the action's error.
enum NOOPShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case notConnected
    case notReady
    case invalidAmount
    case spo2Disabled
    case noSpo2Reading
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConnected:  return "Connect your WHOOP strap in NOOP, then try again."
        case .notReady:      return "NOOP isn't ready yet. Try again in a moment."
        case .invalidAmount: return "Enter an amount above 0 ml."
        case .spo2Disabled:  return "Turn on Settings > Experimental · Blood Oxygen in NOOP first."
        case .noSpo2Reading: return "No blood oxygen estimate yet. Wear your strap overnight and sync it."
        }
    }
}

/// Send a confirming haptic buzz to the strap WITHOUT opening NOOP, so it can run from a personal automation,
/// the Action button or a lock-screen Shortcut. Same idea as `SyncStrapIntent`: iOS runs an in-app intent inside
/// NOOP's own process (launching or resuming it in the background), where the strap link lives under the
/// bluetooth-central background mode. The macOS twin (Strand/System/NOOPAppIntents.swift) has always worked this way.
///
/// A cold background launch has to reconnect and bond first, so wait briefly for a bonded link, then fire the
/// one-shot buzz. No bond within the wait → fail with a clear error rather than park the buzz for the next
/// foreground, where a vibration minutes later would only be confusing.
struct BuzzStrapIntent: AppIntent {
    static var title: LocalizedStringResource = "Buzz Strap"
    static var description = IntentDescription("Send a haptic buzz to your WHOOP strap.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await AppModel.waitForBondedStrap(seconds: 10) else { throw NOOPShortcutError.notConnected }
        // #921: the one-shot routine sends the confirmed sequence, acknowledged, so a busy link can't drop it.
        AppModel.shared?.buzzStrapOnce()
        // The buzz writes are acknowledged; give the acks a moment before the intent returns and iOS may suspend
        // the background-launched process.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return .result()
    }
}

/// Pull the strap's stored history now: the Shortcuts twin of the "Sync now" button, run WITHOUT opening NOOP.
/// iOS runs an in-app intent inside NOOP's own process (launching or resuming it in the background), where the
/// strap link lives under the bluetooth-central background mode, so the offload carries on after this returns.
/// The spoken/shown reply reports only what this path observed about the sync starting.
///
/// `LiveActivityIntent`, not plain `AppIntent`: that is what lets it START the strap-sync Live Activity
/// (the Dynamic Island "Connecting… / Syncing… N chunks" readout) from the background. A plain intent
/// running in a background-launched app is refused by ActivityKit.
struct SyncStrapIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Sync Strap"
    static var description = IntentDescription("Pull your WHOOP strap's stored history into NOOP now.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await AppModel.startStrapSyncFromShortcut() {
        case .started:               return .result(dialog: "Syncing your strap.")
        case .alreadyRunning:        return .result(dialog: "Your strap is already syncing.")
        case .willSyncWhenConnected: return .result(dialog: "NOOP is connecting to your strap and will sync as soon as it's ready.")
        case .strapNotReady:         return .result(dialog: "Your strap isn't connected to NOOP yet, so the sync didn't start.")
        case .notStarted:            return .result(dialog: "NOOP couldn't start the sync. Open NOOP to see the strap log.")
        }
    }
}

/// K9: Ask the Coach a question via Siri. Queues the question and opens the app, which sends it
/// to the configured provider and surfaces the response. The question is spoken or typed in Siri;
/// the app handles the actual network call using the user's saved key.
struct AskCoachIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Coach"
    static var description = IntentDescription("Ask your NOOP Coach a question about your recovery, sleep, or training.")
    static var openAppWhenRun = true

    /// The question to ask, populated by Siri from the user's spoken phrase.
    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingIntents.appendAskCoach(question: question, at: Date())
        return .result(dialog: "Opening Coach with your question: \(question)")
    }
}

/// Buzz the current time out on the strap (Haptic Clock, #460) WITHOUT opening NOOP: long buzzes for tens, short for
/// units, hours then minutes. The pulses are scheduled on the main queue, so the intent stays running until the last
/// one has fired; otherwise iOS could suspend the background-launched process mid-time.
struct BuzzTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Buzz the time"
    static var description = IntentDescription("Buzz the current time on your WHOOP strap.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await AppModel.waitForBondedStrap(seconds: 10), let model = AppModel.shared else {
            throw NOOPShortcutError.notConnected
        }
        let now = Date()
        let is24h = AppModel.localeUses24HourClock
        model.ble.buzzTimeNow(is24h: is24h, at: now)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let pulses = HapticClock.pulses(hour: comps.hour ?? 0, minute: comps.minute ?? 0, is24h: is24h)
        let totalMs = pulses.reduce(0) { $0 + $1.durationMs + $1.gapMs }
        // Capped well inside the time iOS grants a background intent.
        let waitMs = min(totalMs + 1_000, 25_000)
        try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000)
        return .result()
    }
}

/// Log a caffeine intake WITHOUT opening NOOP (#2266). The amount is optional, like the card: nil = "I had caffeine".
/// The intake is stamped with the invocation time. Writes the same process-wide store the Caffeine card reads.
struct LogCaffeineIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Caffeine"
    static var description = IntentDescription("Log a caffeine intake in NOOP without opening the app.")
    static var openAppWhenRun = false

    @Parameter(title: "Caffeine (mg)")
    var mg: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        CaffeineLogStore.shared.log(at: Date(), mg: mg.map(Double.init))
        return .result(dialog: "Caffeine logged.")
    }
}

/// Add a drink to today's hydration WITHOUT opening NOOP (#2266). Same additive quick-add as the Hydration card.
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Add a drink to today's hydration in NOOP without opening the app.")
    static var openAppWhenRun = false

    @Parameter(title: "Amount (ml)", default: 250)
    var amountMl: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amountMl > 0 else { throw NOOPShortcutError.invalidAmount }
        guard let model = await AppModel.waitForModel(seconds: 8) else { throw NOOPShortcutError.notReady }
        await model.repo.logHydration(amountMl: amountMl)
        return .result(dialog: "Water logged.")
    }
}

/// Which sleep mark the "Log a sleep mark" shortcut records.
enum SleepMarkKind: String, AppEnum {
    case bedtime
    case wake

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep Mark"
    static var caseDisplayRepresentations: [SleepMarkKind: DisplayRepresentation] = [
        .bedtime: "Going to sleep",
        .wake: "I'm awake",
    ]

    var markType: SleepMarkType { self == .wake ? .wake : .bedtime }
}

/// Log a bedtime or wake mark WITHOUT opening NOOP (#2266), stamped with the invocation time. Unlike the strap
/// double-tap it can choose the type. Goes through `markSleep`, so it also buzzes the strap when it is connected.
struct LogSleepMarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a sleep mark"
    static var description = IntentDescription("Mark going to sleep or waking up in NOOP without opening the app.")
    static var openAppWhenRun = false

    @Parameter(title: "Sleep Mark", default: .bedtime)
    var kind: SleepMarkKind

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        guard let model = await AppModel.waitForModel(seconds: 8) else { throw NOOPShortcutError.notReady }
        model.markSleep(at: now, type: kind.markType)
        // markSleep writes its metric-series row from a detached Task; give it a moment before the intent
        // returns and iOS may suspend the background-launched process.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return .result(dialog: "Sleep mark logged.")
    }
}

/// Read the most recent nightly SpO₂ strap estimate (#103, the WHOOP 5/MG `spo2_candidate_82` mean; Oura's capped
/// mean on a ring) WITHOUT opening NOOP, and hand it to the Shortcut as a number. Display-only and unverified like the
/// Blood Oxygen tile it mirrors: it only answers while the "Experimental · Blood Oxygen" toggle is on, because the
/// engine computes the candidate only then.
struct GetBloodOxygenIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Blood Oxygen"
    static var description = IntentDescription("Last night's SpO₂ strap estimate from your WHOOP 5.0/MG. Experimental and unverified.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard PuffinExperiment.spo2CandidateDisplayEnabled else { throw NOOPShortcutError.spo2Disabled }
        guard let model = await AppModel.waitForModel(seconds: 8) else { throw NOOPShortcutError.notReady }
        // Same key + source the Today Blood Oxygen tile reads; ascending by day, so the last row is the newest night.
        let series = await model.repo.exploreSeries(key: "spo2_candidate", source: "my-whoop", days: 3)
        guard let newest = series.last else { throw NOOPShortcutError.noSpo2Reading }
        let pct = Int(newest.value.rounded())
        let pctText = "\(pct) %"
        return .result(value: pct, dialog: "Blood oxygen on \(newest.day): \(pctText) (strap estimate, unverified)")
    }
}

/// Surfaces NOOP's intents to Siri, Spotlight, and the Shortcuts gallery without any user setup.
struct NOOPShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SyncStrapIntent(),
                    phrases: [
                        "Sync my \(.applicationName) strap",
                        "Sync \(.applicationName)",
                    ],
                    shortTitle: "Sync Strap",
                    systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: MarkMomentIntent(),
                    phrases: ["Mark a moment in \(.applicationName)"],
                    shortTitle: "Mark a Moment",
                    systemImageName: "mappin.and.ellipse")
        AppShortcut(intent: BuzzStrapIntent(),
                    phrases: ["Buzz my \(.applicationName) strap"],
                    shortTitle: "Buzz Strap",
                    systemImageName: "waveform.path")
        AppShortcut(intent: BuzzTimeIntent(),
                    phrases: ["Buzz the time with \(.applicationName)"],
                    shortTitle: "Buzz the time",
                    systemImageName: "clock")
        AppShortcut(intent: LogCaffeineIntent(),
                    phrases: ["Log caffeine in \(.applicationName)"],
                    shortTitle: "Log Caffeine",
                    systemImageName: "cup.and.saucer")
        AppShortcut(intent: LogWaterIntent(),
                    phrases: ["Log water in \(.applicationName)"],
                    shortTitle: "Log Water",
                    systemImageName: "drop")
        AppShortcut(intent: LogSleepMarkIntent(),
                    phrases: ["Log a sleep mark in \(.applicationName)"],
                    shortTitle: "Log a sleep mark",
                    systemImageName: "bed.double")
        // AppShortcutsProvider allows at most 10 entries; this is the ninth.
        AppShortcut(intent: GetBloodOxygenIntent(),
                    phrases: ["Get my blood oxygen from \(.applicationName)"],
                    shortTitle: "Blood Oxygen",
                    systemImageName: "lungs")
        // K9: "Ask Coach" via Siri — opens Coach with the question and sends it. The question
        // parameter is provided via the Shortcuts app or Siri prompts for it when the phrase fires.
        AppShortcut(intent: AskCoachIntent(),
                    phrases: [
                        "Ask \(.applicationName) about my recovery",
                        "Ask \(.applicationName) how I'm doing",
                        "Ask \(.applicationName) Coach",
                    ],
                    shortTitle: "Ask Coach",
                    systemImageName: "sparkles")
    }
}
#endif
