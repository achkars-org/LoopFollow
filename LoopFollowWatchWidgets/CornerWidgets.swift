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
                    Text(entry.label([entry.cornerArrowText, entry.ageText]))
                }
                .tint(entry.ageColor)
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

    /// The gauge fills over 20 minutes, the point at which the age colour turns red.
    private static let gaugeSpan: TimeInterval = 20 * 60

    /// 0 for a fresh reading, 1 at 20 minutes old or more.
    var cornerStaleness: Double {
        guard let readingAge else { return 1 }
        return min(max(readingAge / Self.gaugeSpan, 0), 1)
    }

    /// Green under 10 minutes, yellow under 20, red beyond.
    var ageColor: Color {
        guard let readingAge else { return .red }
        if readingAge < 10 * 60 {
            return .green
        }
        return readingAge < Self.gaugeSpan ? .yellow : .red
    }
}
