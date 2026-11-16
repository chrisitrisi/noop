import SwiftUI
import StrandDesign

/// "Days in a row with the strap on", pinned near the top of Today with a living flame.
///
/// The count is `WearStreak` over the banked days (`Repository.days`), so it reads the same numbers as
/// every other Today figure. The flame grows with the streak and burns hotter at milestones (7, 30, 100
/// days); while today has no data yet it dims to embers and the caption asks for today's wear. Reduce
/// Motion gets a still flame. Self-hides until there is a streak to show.
struct WearStreakCard: View {
    @EnvironmentObject var repo: Repository

    private var result: WearStreak.Result {
        let worn = Set(repo.days.filter {
            WearStreak.isWorn(restingHr: $0.restingHr, strain: $0.strain, totalSleepMin: $0.totalSleepMin)
        }.map(\.day))
        return WearStreak.compute(wornDays: worn, today: Repository.logicalDayKey(Date()))
    }

    var body: some View {
        let r = result
        if r.current > 0 {
            HStack(alignment: .center, spacing: NoopMetrics.space3) {
                StreakFlame(intensity: Self.intensity(days: r.current), lit: r.wornToday)
                    .frame(width: 84, height: 104)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("WEAR STREAK")
                        .font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                        .foregroundStyle(StrandPalette.statusWarning)
                    HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                        Text("\(r.current)")
                            .font(StrandFont.display(48))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(r.current == 1 ? "day" : "days in a row")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    Text(r.wornToday ? Self.milestoneLine(r) : "Wear it today to keep the fire burning")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, NoopMetrics.space3)
            .padding(.horizontal, NoopMetrics.space3)
            .background(NoopPanelSurface(cornerRadius: 26, elevated: true))
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        }
    }

    /// 0...1 flame size: grows over the first month, then holds.
    static func intensity(days: Int) -> Double { min(1, 0.45 + Double(days) / 55) }

    private static func milestoneLine(_ r: WearStreak.Result) -> LocalizedStringKey {
        switch r.current {
        case 100...: return "Legendary. 100 days and counting"
        case 30...:  return "A month on fire"
        case 7...:   return "A full week, keep it burning"
        default:     return r.best > r.current ? "Best: \(r.best) days" : "Your longest streak yet"
        }
    }
}

/// A layered, flickering flame with rising embers, drawn on a Canvas each animation frame.
private struct StreakFlame: View {
    /// 0...1, the flame's size and the number of embers.
    let intensity: Double
    /// Burning (today worn) or glowing embers (today still open).
    let lit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Canvas { ctx, size in draw(in: &ctx, size: size, t: 0) }
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    draw(in: &ctx, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let scale = lit ? intensity : intensity * 0.55
        let base = CGPoint(x: size.width / 2, y: size.height * 0.95)

        // Glow under the flame
        let glowRect = CGRect(x: base.x - size.width * 0.45, y: base.y - size.height * 0.22,
                              width: size.width * 0.9, height: size.height * 0.3)
        ctx.fill(Path(ellipseIn: glowRect),
                 with: .radialGradient(Gradient(colors: [StrandPalette.statusCritical.opacity(lit ? 0.45 : 0.25),
                                                         StrandPalette.statusCritical.opacity(0)]),
                                       center: CGPoint(x: glowRect.midX, y: glowRect.midY),
                                       startRadius: 0, endRadius: size.width * 0.45))

        // Three tongues of fire, outer to core, each with its own flicker
        let layers: [(Color, Double, Double)] = [
            (StrandPalette.statusCritical, 1.0, 0.0),
            (StrandPalette.statusWarning, 0.72, 1.7),
            (StrandPalette.goldDeepText, 0.38, 3.1),
        ]
        for (color, size01, phase) in layers {
            let h = size.height * 0.88 * scale * size01 * (1 + 0.06 * sin(t * 9 + phase))
            let w = size.width * 0.62 * scale * size01 * (1 + 0.04 * sin(t * 7 + phase * 2))
            let sway = size.width * 0.06 * scale * sin(t * 3.3 + phase)
            ctx.fill(flamePath(base: base, width: w, height: h, sway: sway, t: t + phase),
                     with: .linearGradient(Gradient(colors: [color, color.opacity(lit ? 0.85 : 0.5)]),
                                           startPoint: base, endPoint: CGPoint(x: base.x, y: base.y - h)))
        }

        // Embers drifting up and fading
        guard lit else { return }
        let count = 4 + Int(intensity * 8)
        for i in 0..<count {
            let seed = Double(i) * 12.9898
            let period = 1.4 + (sin(seed) + 1) * 0.6
            let progress = ((t + seed) / period).truncatingRemainder(dividingBy: 1)
            let x = base.x + size.width * 0.3 * sin(seed * 3 + progress * 4) * scale
            let y = base.y - size.height * (0.3 + progress * 0.75) * scale
            let r = 1.2 + 1.6 * (1 - progress)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(StrandPalette.statusWarning.opacity(1 - progress)))
        }
    }

    /// A teardrop flame: round belly at the base, tip swaying with time.
    private func flamePath(base: CGPoint, width w: Double, height h: Double, sway: Double, t: Double) -> Path {
        var p = Path()
        let tip = CGPoint(x: base.x + sway, y: base.y - h)
        let lick = 0.08 * w * sin(t * 11)
        p.move(to: CGPoint(x: base.x, y: base.y))
        p.addCurve(to: tip,
                   control1: CGPoint(x: base.x - w * 0.75, y: base.y - h * 0.15),
                   control2: CGPoint(x: base.x - w * 0.15 + lick, y: base.y - h * 0.65))
        p.addCurve(to: CGPoint(x: base.x, y: base.y),
                   control1: CGPoint(x: base.x + w * 0.2 - lick, y: base.y - h * 0.6),
                   control2: CGPoint(x: base.x + w * 0.75, y: base.y - h * 0.15))
        p.closeSubpath()
        return p
    }
}
