// LoopFollow
// LoopFollowWatchWidgets.swift

import SwiftUI
import WidgetKit

struct GlucoseComplicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.glucose, provider: GlucoseTimelineProvider()) { entry in
            GlucoseComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("LoopFollow")
        .description("Current glucose, trend and recent history.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct LoopFollowWatchWidgets: WidgetBundle {
    var body: some Widget {
        GlucoseComplicationWidget()
        GaugeCornerWidget()
        StackCornerWidget()
        BolusShortcutWidget()
        MealShortcutWidget()
        OverrideShortcutWidget()
        #if DEBUG
            DebugComplicationWidget()
        #endif
    }
}
