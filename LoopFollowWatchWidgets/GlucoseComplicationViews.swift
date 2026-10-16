// LoopFollow
// GlucoseComplicationViews.swift

import Charts
import SwiftUI
import WidgetKit

struct GlucoseComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlucoseEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularGlucoseView(entry: entry)
        case .accessoryCorner:
            CornerGlucoseView(entry: entry)
        case .accessoryInline:
            InlineGlucoseView(entry: entry)
        default:
            EmptyView()
        }
    }
}

// MARK: - Shared values

private extension GlucoseEntry {
    var glucoseText: String {
        guard let snapshot, !isExpired else { return "--" }
        return WatchFormat.glucose(snapshot)
    }

    var arrowText: String {
        guard let snapshot, !isStale else { return "" }
        return WatchFormat.trendArrow(snapshot)
    }

    var deltaText: String {
        guard let snapshot, !isStale else { return "" }
        return WatchFormat.delta(snapshot)
    }

    var color: Color {
        guard let snapshot, !isStale else { return .yellow }
        return GlucoseColor.color(forMgdl: snapshot.glucose)
    }
}

// MARK: - Corner

private struct CornerGlucoseView: View {
    let entry: GlucoseEntry

    var body: some View {
        Text(entry.glucoseText)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(entry.color)
            .privacySensitive()
            .widgetCurvesContent()
            .widgetLabel(entry.label([entry.deltaText, entry.arrowText, entry.ageText]))
    }
}

// MARK: - Inline

private struct InlineGlucoseView: View {
    let entry: GlucoseEntry

    var body: some View {
        Text("\(entry.glucoseText) \(entry.arrowText) \(entry.deltaOrAge(delta: entry.deltaText))")
            .privacySensitive()
    }
}

// MARK: - Rectangular

/// BG, trend, delta and age on the left with a two-hour sparkline on the right.
private struct RectangularGlucoseView: View {
    let entry: GlucoseEntry

    private var sparkline: [WatchGlucoseHistory.Point] {
        let cutoff = entry.date.timeIntervalSince1970 - 2 * 60 * 60
        return entry.history.filter { $0.date >= cutoff }
    }

    /// Vertical range padded around the data so a flat stretch still reads as a line.
    private var chartDomain: ClosedRange<Double> {
        let values = sparkline.map { Double($0.mgdl) }
        guard let low = values.min(), let high = values.max() else { return 70 ... 180 }
        let pad = max((high - low) * 0.15, 10)
        return (low - pad) ... (high + pad)
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(entry.glucoseText)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(entry.color)
                        .minimumScaleFactor(0.6)
                    Text(entry.arrowText)
                        .font(.system(size: 16, weight: .semibold))
                }
                .privacySensitive()
                Text(entry.isStale ? entry.ageText : "\(entry.deltaText) · \(entry.ageText)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()

            if sparkline.count > 1 {
                Chart(sparkline, id: \.date) { point in
                    LineMark(
                        x: .value("time", point.date),
                        y: .value("bg", point.mgdl)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(entry.color)

                    if point.date == sparkline.last?.date {
                        PointMark(
                            x: .value("time", point.date),
                            y: .value("bg", point.mgdl)
                        )
                        .symbolSize(24)
                        .foregroundStyle(entry.color)
                    }
                }
                .chartYScale(domain: chartDomain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .widgetAccentable()
            }
        }
    }
}
