import SwiftUI
import StrandDesign

/// The "Drinks" tab (fork extra, iPhone): the one-tap `IntakeQuickCard` on top, the full Caffeine card
/// (bedtime cutoff, intake list, custom amounts) below it. Both read and write the same stores as Today's
/// hosted card, the Hydration screen and Insights, so every copy shows the same numbers.
struct DrinksScreen: View {
    var body: some View {
        ScreenScaffold(title: "Drinks & caffeine",
                       subtitle: "Water and caffeine today, logged in one tap.",
                       topBackground: liquidScaffoldSky()) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                IntakeQuickCard()
                CaffeineLogCard()
            }
        }
    }
}
