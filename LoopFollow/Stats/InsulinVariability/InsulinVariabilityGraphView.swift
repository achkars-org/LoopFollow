// LoopFollow
// InsulinVariabilityGraphView.swift

import Charts
import SwiftUI

struct InsulinVariabilityGraphView: View {
    let data: [InsulinVariabilityDataPoint]

    enum Component: String, CaseIterable, Plottable {
        case basal = "Basal & automatic"
        case meal = "Meal boluses"

        var color: Color {
            switch self {
            case .basal: return .blue.opacity(0.75)
            case .meal: return .orange.opacity(0.75)
            }
        }
    }

    private struct Slice: Identifiable {
        let period: TIRPeriod
        let component: Component
        let value: Double
        var id: String { "\(period.rawValue)-\(component.rawValue)" }
    }

    private var slices: [Slice] {
        data.flatMap { point in
            [
                Slice(period: point.period, component: .basal, value: point.basalDeviation),
                Slice(period: point.period, component: .meal, value: point.mealDeviation),
            ]
        }
    }

    var body: some View {
        Chart {
            ForEach(slices) { slice in
                BarMark(
                    x: .value("period", slice.period.rawValue),
                    y: .value("pct", slice.value),
                    width: .ratio(0.6)
                )
                .foregroundStyle(by: .value("component", slice.component))
            }

            RuleMark(y: .value("plan", 0))
                .foregroundStyle(Color.primary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(data, id: \.period) { point in
                PointMark(
                    x: .value("period", point.period.rawValue),
                    y: .value("pct", point.variability)
                )
                .symbol(.diamond)
                .foregroundStyle(Color.primary)
                .annotation(position: point.variability >= 0 ? .top : .bottom) {
                    Text(String(format: "%+.0f%%", point.variability))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .chartForegroundStyleScale(domain: Component.allCases, range: Component.allCases.map(\.color))
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [5, 5]))
                AxisTick()
                AxisValueLabel {
                    if let pct = value.as(Double.self) {
                        Text(String(format: "%+.0f%%", pct))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisValueLabel()
            }
        }
        .allowsHitTesting(false)
        .background(Color(.systemBackground))
    }
}
