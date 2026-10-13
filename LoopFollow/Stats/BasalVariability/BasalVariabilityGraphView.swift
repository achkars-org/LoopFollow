// LoopFollow
// BasalVariabilityGraphView.swift

import Charts
import SwiftUI

struct BasalVariabilityGraphView: View {
    let data: [BasalVariabilityDataPoint]

    private enum Band: String, CaseIterable, Plottable {
        case suspended = "Suspended"
        case veryBelow = "< 50%"
        case below = "50–75%"
        case atPlanned = "75–125%"
        case above = "125–150%"
        case veryAbove = "> 150%"

        var color: Color {
            switch self {
            case .suspended: return Color(uiColor: .systemGray).opacity(0.85)
            case .veryBelow: return .blue.opacity(0.85)
            case .below: return Color(uiColor: .systemTeal).opacity(0.65)
            case .atPlanned: return .green.opacity(0.75)
            case .above: return .orange.opacity(0.65)
            case .veryAbove: return .red.opacity(0.75)
            }
        }
    }

    private struct Slice: Identifiable {
        let period: TIRPeriod
        let band: Band
        let value: Double
        var id: String { "\(period.rawValue)-\(band.rawValue)" }
    }

    private var slices: [Slice] {
        data.flatMap { point in
            [
                Slice(period: point.period, band: .suspended, value: point.suspended),
                Slice(period: point.period, band: .veryBelow, value: point.veryBelow),
                Slice(period: point.period, band: .below, value: point.below),
                Slice(period: point.period, band: .atPlanned, value: point.atPlanned),
                Slice(period: point.period, band: .above, value: point.above),
                Slice(period: point.period, band: .veryAbove, value: point.veryAbove),
            ]
        }
    }

    var body: some View {
        Chart(slices) { slice in
            BarMark(
                x: .value("period", slice.period.rawValue),
                y: .value("pct", slice.value),
                width: .ratio(0.6)
            )
            .foregroundStyle(by: .value("band", slice.band))
        }
        .chartForegroundStyleScale(domain: Band.allCases, range: Band.allCases.map(\.color))
        .chartLegend(.hidden)
        .chartYScale(domain: 0 ... 102)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [5, 5]))
                AxisTick()
                AxisValueLabel {
                    if let pct = value.as(Int.self) {
                        Text("\(pct)%")
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
