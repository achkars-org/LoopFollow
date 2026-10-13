// LoopFollow
// GlucoseChartView.swift

import Charts
import SwiftUI

/// Recent BG readings with the low/high lines, synced from the iPhone.
struct GlucoseChartView: View {
    let points: [WatchGlucoseHistory.Point]
    let unit: GlucoseSnapshot.Unit

    /// Hours shown; the phone sends three.
    private let hours = 3.0

    private var thresholds: (low: Double, high: Double) { LAAppGroupSettings.thresholdsMgdl() }

    private func display(_ mgdl: Double) -> Double {
        unit == .mmol ? GlucoseConversion.toMmol(mgdl) : mgdl
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map { Double($0.mgdl) } + [thresholds.low, thresholds.high]
        let low = max(0, (values.min() ?? 40) - 10)
        let high = (values.max() ?? 300) + 10
        return display(low) ... display(high)
    }

    var body: some View {
        if points.count < 2 {
            Text("Waiting for readings")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Chart {
                RuleMark(y: .value("low", display(thresholds.low)))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("high", display(thresholds.high)))
                    .foregroundStyle(.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                ForEach(points, id: \.date) { point in
                    PointMark(
                        x: .value("time", Date(timeIntervalSince1970: point.date)),
                        y: .value("bg", display(Double(point.mgdl)))
                    )
                    .symbolSize(12)
                    .foregroundStyle(GlucoseColor.color(forMgdl: Double(point.mgdl), thresholds: thresholds))
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-hours * 3600) ... Date())
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
            }
            .padding(.horizontal, 2)
        }
    }
}
