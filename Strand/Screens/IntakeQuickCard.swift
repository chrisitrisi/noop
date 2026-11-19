import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Drinks & caffeine quick-log card (fork extra, hosted on Today)
//
// One card for the things logged many times a day: a water tube that splashes when a drink lands, two
// big water buttons (0.25 / 0.5 L), what logged caffeine is likely to leave at bedtime, and a scrolling
// row of one-tap drinks (more water sizes, espresso, coffee, tea, mate, cola, energy drink).
//
// It keeps no data of its own. Water goes through `Repository.logHydration` (the Hydration screen's
// store and the Today hydration tile's source); caffeine goes into `CaffeineLogStore.shared` (the
// Caffeine card's store and decay estimate). Bedtime is the Caffeine card's own setting, so the two
// readouts resolve from the same intakes and the same bedtime and cannot disagree.
struct IntakeQuickCard: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore
    @ObservedObject private var caffeine = CaffeineLogStore.shared
    @AppStorage(CaffeineLogCard.bedtimeMinutesKey) private var bedtimeMinutes = 23 * 60

    /// Today's water (ml), re-read whenever any hydration write bumps `hydrationSeq`.
    @State private var totalML: Double = 0
    /// Bumped per water log: replays the splash on the tube.
    @State private var splashTick = 0
    /// Bumped per log of any kind: drives the success haptic.
    @State private var loggedTick = 0
    /// "Logged: Espresso", so a tap on a chip has a visible answer.
    @State private var lastLogged: String?

    private var goalML: Int { repo.hydrationGoalML(profileSex: profile.sex) }
    private var fraction: Double { HydrationGoal.fraction(totalML: totalML, goalML: goalML) }

    var body: some View {
        NoopCard(tint: StrandPalette.metricCyan) {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                Text("Drinks & caffeine").strandOverline()
                waterSection
                Divider().overlay(StrandPalette.hairline)
                caffeineSection
                chipRow
                if let lastLogged {
                    Text(verbatim: lastLogged)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .task(id: repo.hydrationSeq) { await reload() }
        .strandHaptic(.success, trigger: loggedTick)
    }

    // MARK: Water

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
            HStack {
                Text("Hydration")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Text(verbatim: HydrationGoal.cardValueString(totalML: totalML, goalML: goalML))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .monospacedDigit()
            }
            LiquidTube(frac: fraction, tint: StrandPalette.metricCyan, height: 18)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        SplashBurst(trigger: splashTick, tint: StrandPalette.metricCyan)
                            .position(x: max(12, geo.size.width * fraction), y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
            HStack(spacing: NoopMetrics.gap) {
                ForEach(IntakePreset.primaryWater) { preset in
                    Button { log(preset) } label: {
                        Label { Text(verbatim: preset.title) } icon: { Image(systemName: "plus") }
                    }
                    .buttonStyle(NoopButtonStyle(.secondary, fullWidth: true))
                }
            }
        }
    }

    // MARK: Caffeine

    private var caffeineSection: some View {
        let estimate = caffeine.estimate()
        let now = Date()
        let bedtime = CaffeineAtBedtime.upcomingBedtime(now: now, bedtimeMinutes: bedtimeMinutes)
        let atBedtime = bedtime.flatMap {
            CaffeineAtBedtime.remainingMg(intakes: caffeine.intakes, now: now, bedtime: $0)
        }
        return HStack(alignment: .top, spacing: NoopMetrics.gap) {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(StrandPalette.metricAmber)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: activeLine(estimate))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let bedtime, let mg = atBedtime, mg >= 1 {
                    let time = AppClock.hourMinuteFormatter().string(from: bedtime)
                    Text("At bedtime (\(time)) about \(Int(mg.rounded())) mg remain")
                        .font(StrandFont.footnote)
                        .foregroundStyle(mg >= CaffeineAtBedtime.sleepRelevantMg
                                         ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Same wording and the same keys as the Caffeine card's headline, so both translate alike.
    private func activeLine(_ est: CaffeineActiveEstimate) -> String {
        if let mg = est.totalRemainingMg, est.hasActive {
            return String(localized: "About \(Int(mg.rounded())) mg may still be active")
        }
        if est.hasActive { return String(localized: "Caffeine may still be active") }
        return caffeine.intakes.isEmpty
            ? String(localized: "No caffeine logged. Log an intake to see an estimate.")
            : String(localized: "Estimated mostly cleared. Nothing logged is likely still active.")
    }

    // MARK: Chips

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NoopMetrics.gap) {
                ForEach(IntakePreset.chips) { preset in
                    Button { log(preset) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: preset.systemImage)
                            Text(verbatim: preset.title)
                            if let dose = preset.doseLabel {
                                Text(verbatim: dose)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                        .font(StrandFont.footnote)
                    }
                    .buttonStyle(NoopButtonStyle(.tertiary))
                }
            }
        }
    }

    // MARK: Logging

    private func log(_ preset: IntakePreset) {
        switch preset.kind {
        case .water(let ml):
            splashTick += 1
            // logHydration bumps hydrationSeq, which re-runs the reload task above.
            Task { await repo.logHydration(amountMl: ml) }
        case .caffeine(let mg):
            caffeine.log(at: Date(), mg: Double(mg))
        }
        loggedTick += 1
        lastLogged = String(localized: "Logged: \(preset.title)")
    }

    private func reload() async {
        totalML = await repo.hydrationTotal(day: Repository.localDayKey(Date()))
    }
}

/// A handful of drops thrown up from the water line when a drink lands. Decorative only: hidden from
/// VoiceOver and skipped entirely under Reduce Motion.
private struct SplashBurst: View {
    let trigger: Int
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    /// Where each drop ends up relative to the water line, and how large it is.
    private static let drops: [(dx: CGFloat, dy: CGFloat, scale: CGFloat)] = [
        (-26, -20, 0.7), (-12, -32, 0.55), (2, -26, 0.9), (16, -34, 0.5), (28, -18, 0.65),
    ]

    var body: some View {
        ZStack {
            ForEach(Self.drops.indices, id: \.self) { i in
                let drop = Self.drops[i]
                Image(systemName: "drop.fill")
                    .imageScale(.small)
                    .foregroundStyle(tint)
                    .scaleEffect(drop.scale * (0.6 + 0.4 * progress))
                    .offset(x: drop.dx * progress, y: drop.dy * progress)
                    .opacity(Double(1 - progress))
            }
        }
        .accessibilityHidden(true)
        .onChangeCompat(of: trigger) { _ in
            guard !reduceMotion else { return }
            progress = 0
            withAnimation(.easeOut(duration: 0.7)) { progress = 1 }
        }
    }
}
