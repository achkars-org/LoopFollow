// LoopFollow
// StatsPageView.swift

import SwiftUI

/// The iPhone's 24-hour statistics for the current unit.
struct StatsPageView: View {
    let stats: WatchStatsSummary?
    let unit: GlucoseSnapshot.Unit

    private func glucose(_ mgdl: Double) -> String {
        unit == .mmol ? String(format: "%.1f", GlucoseConversion.toMmol(mgdl)) : "\(Int(mgdl.rounded()))"
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    var body: some View {
        if let stats {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 24 hours")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    RangeBar(stats: stats)
                        .frame(height: 10)

                    HStack {
                        StatCell(label: "Low", value: percent(stats.lowPercent), color: .red)
                        StatCell(label: "In range", value: percent(stats.inRangePercent), color: .green)
                        StatCell(label: "High", value: percent(stats.highPercent), color: .orange)
                    }

                    Text("Range \(glucose(stats.lowMgdl))–\(glucose(stats.highMgdl)) \(unit.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        StatCell(label: "Average", value: glucose(stats.averageMgdl), color: .primary)
                        StatCell(label: "SD", value: glucose(stats.standardDeviationMgdl), color: .primary)
                        StatCell(label: "GMI", value: String(format: "%.1f%%", stats.gmiPercent), color: .primary)
                    }
                }
                .padding(.horizontal, 4)
            }
        } else {
            Text("No statistics yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RangeBar: View {
    let stats: WatchStatsSummary

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                Color.red.frame(width: geo.size.width * stats.lowPercent / 100)
                Color.green.frame(width: geo.size.width * stats.inRangePercent / 100)
                Color.orange.frame(width: geo.size.width * stats.highPercent / 100)
            }
            .clipShape(Capsule())
        }
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
