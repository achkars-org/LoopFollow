// LoopFollow
// CornerWidgets.swift

import SwiftUI
import WidgetKit

/// Corner complication: BG with the projected BG stacked beneath it.
struct StackCornerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.stackCorner, provider: GlucoseTimelineProvider()) { entry in
            StackCornerView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("LoopFollow Projected")
        .description("Glucose with projected glucose.")
        .supportedFamilies([.accessoryCorner])
    }
}

private struct StackCornerView: View {
    let entry: GlucoseEntry

    private var projectedText: String {
        guard let snapshot = entry.snapshot, !entry.isProjectionExpired else { return "--" }
        return WatchFormat.projected(snapshot)
    }

    var body: some View {
        Text(entry.cornerGlucoseText)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(entry.cornerColor)
            .privacySensitive()
            .widgetCurvesContent()
            .widgetLabel(entry.label([entry.cornerArrowText, projectedText, entry.ageText]))
    }
}

private extension GlucoseEntry {
    var cornerGlucoseText: String {
        guard let snapshot, !isExpired else { return "--" }
        return WatchFormat.glucose(snapshot)
    }

    var cornerArrowText: String {
        guard let snapshot, !isStale else { return "" }
        return WatchFormat.trendArrow(snapshot)
    }

    var cornerColor: Color {
        guard let snapshot, !isStale else { return .yellow }
        return GlucoseColor.color(forMgdl: snapshot.glucose)
    }
}
