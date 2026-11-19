import Foundation

// MARK: - Drinks & caffeine quick-log presets (fork extra, iOS + macOS)
//
// The one-tap drinks offered by `IntakeQuickCard`. Water presets add to the day's hydration total
// (`Repository.logHydration`); caffeine presets log one intake into the shared `CaffeineLogStore`, the
// same store the Caffeine card and its decay estimate read, so nothing here keeps a second copy.
//
// Caffeine amounts are typical values per serving (rounded, in the range EFSA and common nutrition
// tables give); real drinks vary a lot, which is why the card words its readout as a rough guide.

/// One tap-to-log drink.
struct IntakePreset: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Plain water, in millilitres.
        case water(ml: Int)
        /// A caffeinated drink, with its typical caffeine dose in milligrams.
        case caffeine(mg: Int)
    }

    let id: String
    let kind: Kind
    /// SF Symbol for the chip.
    let systemImage: String

    /// The chip label. Water sizes are formatted volumes, caffeine drinks carry a translated name.
    var title: String {
        switch kind {
        case .water(let ml):
            return Self.litres(ml)
        case .caffeine:
            switch id {
            case "espresso": return String(localized: "Espresso")
            case "doubleEspresso": return String(localized: "Double espresso")
            case "coffeeSmall": return String(localized: "Small coffee")
            case "coffeeLarge": return String(localized: "Large coffee")
            case "cappuccino": return String(localized: "Cappuccino")
            case "blackTea": return String(localized: "Black tea")
            case "greenTea": return String(localized: "Green tea")
            case "mate": return String(localized: "Mate (0.5 L)")
            case "cola": return String(localized: "Cola (0.33 L)")
            case "energyDrink": return String(localized: "Energy drink (0.25 L)")
            default: return id
            }
        }
    }

    /// "65 mg" for a caffeinated drink in the reader's locale; nil for water.
    var doseLabel: String? {
        guard case .caffeine(let mg) = kind else { return nil }
        return Measurement(value: Double(mg), unit: UnitMass.milligrams)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    /// "0.25 L" in the reader's locale ("0,25 L" in German).
    static func litres(_ ml: Int) -> String {
        Measurement(value: Double(ml) / 1000, unit: UnitVolume.liters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }

    /// The two big water buttons above the chip row.
    static let primaryWater: [IntakePreset] = [
        IntakePreset(id: "water250", kind: .water(ml: 250), systemImage: "drop.fill"),
        IntakePreset(id: "water500", kind: .water(ml: 500), systemImage: "drop.fill"),
    ]

    /// The scrolling chip row: more water sizes, then the caffeinated drinks.
    static let chips: [IntakePreset] = [
        IntakePreset(id: "water330", kind: .water(ml: 330), systemImage: "drop"),
        IntakePreset(id: "water750", kind: .water(ml: 750), systemImage: "drop"),
        IntakePreset(id: "water1000", kind: .water(ml: 1000), systemImage: "waterbottle"),
        IntakePreset(id: "espresso", kind: .caffeine(mg: 65), systemImage: "cup.and.saucer.fill"),
        IntakePreset(id: "doubleEspresso", kind: .caffeine(mg: 130), systemImage: "cup.and.saucer.fill"),
        IntakePreset(id: "coffeeSmall", kind: .caffeine(mg: 90), systemImage: "mug.fill"),
        IntakePreset(id: "coffeeLarge", kind: .caffeine(mg: 150), systemImage: "mug.fill"),
        IntakePreset(id: "cappuccino", kind: .caffeine(mg: 75), systemImage: "cup.and.saucer.fill"),
        IntakePreset(id: "blackTea", kind: .caffeine(mg: 45), systemImage: "leaf.fill"),
        IntakePreset(id: "greenTea", kind: .caffeine(mg: 30), systemImage: "leaf"),
        IntakePreset(id: "mate", kind: .caffeine(mg: 100), systemImage: "takeoutbag.and.cup.and.straw.fill"),
        IntakePreset(id: "cola", kind: .caffeine(mg: 35), systemImage: "takeoutbag.and.cup.and.straw"),
        IntakePreset(id: "energyDrink", kind: .caffeine(mg: 80), systemImage: "bolt.fill"),
    ]
}

/// How much logged caffeine is estimated to remain at the coming bedtime.
enum CaffeineAtBedtime {
    /// The bedtime this evening at `bedtimeMinutes` after local midnight. Before 04:00 the night that
    /// is already under way still counts (a 01:00 bedtime read at 00:30 is 30 minutes away, not a day).
    /// Nil once that bedtime has passed: there is nothing left to plan for tonight.
    static func upcomingBedtime(now: Date, bedtimeMinutes: Int, calendar: Calendar = .current) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        guard var bedtime = calendar.date(byAdding: .minute, value: bedtimeMinutes, to: startOfToday) else {
            return nil
        }
        // An after-midnight bedtime (e.g. 00:30 stored as 30 min) belongs to the coming night when the
        // evening is still young.
        if bedtimeMinutes < 4 * 60, calendar.component(.hour, from: now) >= 4,
           let next = calendar.date(byAdding: .day, value: 1, to: bedtime) {
            bedtime = next
        }
        return bedtime > now ? bedtime : nil
    }

    /// Milligrams still estimated at `bedtime` from every intake logged up to `now` that carries an
    /// amount. Nil when none of them has an amount (the readout then stays without a number rather
    /// than inventing one). Intakes after `now` are ignored.
    static func remainingMg(intakes: [CaffeineIntake], now: Date, bedtime: Date,
                            halfLifeHours: Double = CaffeineDecay.defaultHalfLifeHours) -> Double? {
        var total = 0.0
        var anyAmount = false
        for intake in intakes where intake.at <= now {
            guard let mg = intake.mg else { continue }
            anyAmount = true
            let hours = bedtime.timeIntervalSince(intake.at) / 3600
            total += CaffeineDecay.remainingMg(doseMg: mg, hoursElapsed: hours, halfLifeHours: halfLifeHours)
        }
        return anyAmount ? total : nil
    }

    /// Above this many milligrams at bedtime the card flags the evening as likely to affect sleep. A
    /// cautious round figure (about half a small coffee), not a clinical threshold.
    static let sleepRelevantMg = 50.0
}
