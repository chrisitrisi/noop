import Foundation

/// The `noop://workout/...` deep links that start and end a manual workout, the URL twin of the
/// Start Workout / End Workout Shortcuts actions.
///
/// Links exist because a ready-made shortcut file cannot rely on app actions in a sideloaded build:
/// AltStore/SideStore rewrite the bundle id per signing team, and an action bound to the original id
/// finds no app. "Open URL" works with whatever id the app was installed under.
///
///     noop://workout/start?sport=Running&zone=2&warmup=5   (zone 1...5 and warmup minutes optional)
///     noop://workout/end
enum WorkoutLink: Equatable {
    case start(sport: String, zone: Int?, warmupSec: Int)
    case end

    /// The command for `url`, nil when it is not a workout link.
    static func parse(_ url: URL) -> WorkoutLink? {
        guard url.scheme?.lowercased() == "noop", url.host?.lowercased() == "workout",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value?.trimmingCharacters(in: .whitespaces)
        }
        switch url.path.lowercased() {
        case "/start":
            let sport = value("sport").flatMap { $0.isEmpty ? nil : $0 } ?? WorkoutCatalog.defaultSportName
            let zone = value("zone").flatMap(Int.init).flatMap { (1...5).contains($0) ? $0 : nil }
            let warmupMin = value("warmup").flatMap(Int.init).map { min(max($0, 0), 30) } ?? 0
            return .start(sport: sport, zone: zone, warmupSec: warmupMin * 60)
        case "/end":
            return .end
        default:
            return nil
        }
    }
}
