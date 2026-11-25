import SwiftUI
import StrandDesign

// MARK: - Daily wear-streak splash (fork extra)
//
// Once per day, the first time the app is in front with the day's data loaded, the wear streak lands
// full screen: a big flame, the count, the same milestone line the Today card shows. A tap anywhere or
// the button dismisses it. The count comes from `WearStreakCard.result(days:)`, the card's own resolver,
// so the splash and the card can never disagree.

/// When the splash is due. Pure so the once-a-day rule is unit-tested.
enum WearStreakSplashPrefs {
    /// The logical day ("YYYY-MM-DD") the splash last showed on.
    static let lastShownDayKey = "noop.wearStreak.splashLastShownDay"
    /// Off switch for the splash (the Today card is unaffected).
    static let enabledKey = "noop.wearStreak.splashEnabled"

    /// Due when it is switched on, there is a streak to celebrate, and it has not shown today yet.
    static func isDue(enabled: Bool, current: Int, lastShownDay: String, today: String) -> Bool {
        enabled && current > 0 && lastShownDay != today
    }
}

/// Watches for the moment the splash is due and shows it over everything below it.
struct WearStreakSplashHost: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(WearStreakSplashPrefs.lastShownDayKey) private var lastShownDay = ""
    @AppStorage(WearStreakSplashPrefs.enabledKey) private var enabled = true
    @State private var showing: WearStreak.Result?

    var body: some View {
        ZStack {
            if let result = showing {
                WearStreakSplash(result: result) { showing = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showing != nil)
        // Re-checked when the days load or change and whenever the app comes to the front.
        .task(id: "\(repo.days.count)-\(scenePhase == .active)") { await showIfDue() }
    }

    private func showIfDue() async {
        guard scenePhase == .active, showing == nil else { return }
        let today = Repository.logicalDayKey(Date())
        let result = WearStreakCard.result(days: repo.days)
        guard WearStreakSplashPrefs.isDue(enabled: enabled, current: result.current,
                                         lastShownDay: lastShownDay, today: today) else { return }
        // A beat for the first screen to settle, so the splash lands on a finished page.
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled, scenePhase == .active else { return }
        lastShownDay = today
        showing = result
    }
}

/// The full-screen "BAM, N days" moment.
struct WearStreakSplash: View {
    let result: WearStreak.Result
    let onDismiss: () -> Void
    @State private var landed = false

    var body: some View {
        ZStack {
            StrandPalette.surfaceBase.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(spacing: NoopMetrics.space3) {
                StreakFlame(intensity: max(0.85, WearStreakCard.intensity(days: result.current)), lit: true)
                    .frame(width: 200, height: 250)
                    .accessibilityHidden(true)
                Text("WEAR STREAK")
                    .font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.statusWarning)
                Text("\(result.current)")
                    .font(StrandFont.display(96))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                Text(result.current == 1 ? "day" : "days in a row")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(result.wornToday ? WearStreakCard.milestoneLine(result)
                                      : "Wear it today to keep the fire burning")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                NoopButton("Keep it burning", systemImage: "flame.fill", action: onDismiss)
                    .padding(.top, NoopMetrics.space2)
            }
            .padding(.horizontal, NoopMetrics.space3)
            .scaleEffect(landed ? 1 : 0.4)
            .opacity(landed ? 1 : 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .strandHaptic(.success, trigger: landed)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { landed = true }
        }
    }
}
