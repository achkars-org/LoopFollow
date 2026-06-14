// LoopFollow
// PredictionDeltaView.swift

import Charts
import SwiftUI

struct PredictionDeltaView: View {
    @ObservedObject var viewModel: PredictionDeltaViewModel

    var body: some View {
        if !viewModel.deltaData.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("30-min Prediction Error (Actual − Predicted, \(Storage.shared.units.value))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                PredictionDeltaGraphView(deltaData: viewModel.deltaData)
                    .frame(height: 200)
                    .padding(.top, 10)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)

                HStack(spacing: 16) {
                    LegendItem(color: .gray.opacity(0.6), label: "5th–95th")
                    LegendItem(color: Color(.systemTeal).opacity(0.7), label: "25th–75th")
                    LegendItem(color: Color(.systemTeal), label: "Median")
                }
                .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct PredictionDeltaGraphView: View {
    let deltaData: [PredictionDeltaDataPoint]

    private enum Percentile: String, CaseIterable, Plottable {
        case p5 = "5th"
        case p25 = "25th"
        case median = "Median"
        case p75 = "75th"
        case p95 = "95th"

        var color: Color {
            switch self {
            case .p5, .p95: return Color(.systemGray).opacity(0.6)
            case .p25, .p75: return Color(.systemTeal).opacity(0.7)
            case .median: return Color(.systemTeal)
            }
        }

        var lineWidth: CGFloat {
            self == .median ? 2.5 : 1.5
        }
    }

    private struct Point: Identifiable {
        let percentile: Percentile
        let hour: Double
        let value: Double
        var id: String { "\(percentile.rawValue)-\(hour)" }
    }

    /// Fixed error-axis boundary the chart clamps to: ±27 mg/dL (±1.5 mmol/L).
    private var boundary: Double {
        Storage.shared.units.value == "mg/dL" ? 27.0 : 1.5
    }

    private var points: [Point] {
        let clampedBoundary = boundary
        let clamp: (Double) -> Double = { min(max($0, -clampedBoundary), clampedBoundary) }
        let sortedData = deltaData.sorted { $0.timeOfDay < $1.timeOfDay }
        return sortedData.flatMap { dp -> [Point] in
            let hour = Double(dp.timeOfDay) / 60.0
            return [
                Point(percentile: .p5, hour: hour, value: clamp(dp.p5)),
                Point(percentile: .p25, hour: hour, value: clamp(dp.p25)),
                Point(percentile: .median, hour: hour, value: clamp(dp.p50)),
                Point(percentile: .p75, hour: hour, value: clamp(dp.p75)),
                Point(percentile: .p95, hour: hour, value: clamp(dp.p95)),
            ]
        }
    }

    private func axisLabel(_ value: Double) -> String {
        guard abs(value) > 0.0001 else { return "0" }
        let format = Storage.shared.units.value == "mg/dL" ? "%.0f" : "%.1f"
        return String(format: value > 0 ? "+\(format)" : format, value)
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color(.systemRed).opacity(0.7))

            ForEach(points) { point in
                LineMark(
                    x: .value("hour", point.hour),
                    y: .value("delta", point.value)
                )
                .foregroundStyle(by: .value("percentile", point.percentile))
                .lineStyle(StrokeStyle(lineWidth: point.percentile.lineWidth))
                .interpolationMethod(.linear)
            }
        }
        .chartForegroundStyleScale(
            domain: Percentile.allCases,
            range: Percentile.allCases.map(\.color)
        )
        .chartLegend(.hidden)
        .chartXScale(domain: 0 ... 24)
        .chartYScale(domain: -boundary ... boundary)
        .chartXAxis {
            AxisMarks(position: .bottom, values: Array(stride(from: 0, through: 24, by: 3))) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(.label).opacity(0.3))
                AxisTick()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text("\(hour)")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [-boundary, 0, boundary]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(.label).opacity(0.3))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(axisLabel(raw))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .background(Color(.systemBackground))
    }
}
