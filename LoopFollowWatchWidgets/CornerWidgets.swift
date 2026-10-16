// LoopFollow
// CornerWidgets.swift

import SwiftUI
import WidgetKit

/// Corner complication: BG with a gauge arc that fills as the reading ages.
struct GaugeCornerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.gaugeCorner, provider: GlucoseTimelineProvider()) { entry in
            GaugeCornerView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("LoopFollow Gauge")
        .description("Glucose with a gauge showing the reading's age.")
        .supportedFamilies([.accessoryCorner])
    }
}

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

private struct GaugeCornerView: View {
    let entry: GlucoseEntry

    var body: some View {
        Text(entry.cornerGlucoseText)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(entry.cornerColor)
            .privacySensitive()
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: entry.cornerStaleness) {
                    Text(entry.cornerArrowText)
                }
                .tint(entry.cornerColor)
            }
    }
}

private struct StackCornerView: View {
    let entry: GlucoseEntry

    private var projectedText: String {
        guard let snapshot = entry.snapshot, !entry.isStale else { return "--" }
        return WatchFormat.projected(snapshot)
    }

    var body: some View {
        Text(entry.cornerGlucoseText)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(entry.cornerColor)
            .privacySensitive()
            .widgetCurvesContent()
            .widgetLabel("\(entry.cornerArrowText) \(projectedText)")
    }
}

private extension GlucoseEntry {
    var cornerGlucoseText: String {
        guard let snapshot, !isStale else { return "--" }
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

    /// 0 for a fresh reading, 1 once it is stale.
    var cornerStaleness: Double {
        guard let readingAge else { return 1 }
        return min(max(readingAge / Self.staleAfter, 0), 1)
    }
}
