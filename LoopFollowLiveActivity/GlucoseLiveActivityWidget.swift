//
//  GlucoseLiveActivityWidget.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-12.
//  Copyright © 2026 Jon Fawcett.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct GlucoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {

        ActivityConfiguration(for: GlucoseLiveActivityAttributes.self) { context in

            // MARK: Lock Screen UI
            let glucoseText = formatGlucose(context.state.glucoseMmol)
            let trendText = formatTrend(context.state.trend)

            let iobText = formatIOB(context.state.iob)
            let cobText = formatCOB(context.state.cob)

            let projectedText = formatGlucose(context.state.projectedMmol)
            let updatedText = formatUpdatedTime(context.state.updatedAt)

            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 12) {

                    // LEFT: BG + Trend
                    VStack(alignment: .leading, spacing: 2) {
                        Text(glucoseText)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .monospacedDigit()

                        Text(trendText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 90, alignment: .leading)

                    Divider()

                    // MIDDLE: IOB / COB
                    VStack(alignment: .leading, spacing: 6) {
                        MetricRow(label: "IOB", value: iobText)
                        MetricRow(label: "COB", value: cobText)
                    }
                    .frame(minWidth: 80, alignment: .leading)

                    Divider()

                    // RIGHT: Projected / Updated
                    VStack(alignment: .leading, spacing: 6) {
                        MetricRow(label: "Proj", value: projectedText)
                        MetricRow(label: "Upd", value: updatedText)
                    }
                    .frame(minWidth: 80, alignment: .leading)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)

        } dynamicIsland: { context in

            let glucoseText = formatGlucose(context.state.glucoseMmol)
            let trendText = formatTrend(context.state.trend)

            let iobText = formatIOB(context.state.iob)
            let cobText = formatCOB(context.state.cob)
            let projectedText = formatGlucose(context.state.projectedMmol)
            let updatedText = formatUpdatedTime(context.state.updatedAt)

            return DynamicIsland {

                // MARK: Expanded
                DynamicIslandExpandedRegion(.center) {
                    HStack(alignment: .center, spacing: 10) {

                        // BG + Trend
                        VStack(alignment: .leading, spacing: 2) {
                            Text(glucoseText)
                                .font(.title2)
                                .bold()
                                .monospacedDigit()
                            Text(trendText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        // IOB / COB
                        VStack(alignment: .leading, spacing: 4) {
                            MetricRow(label: "IOB", value: iobText, compact: true)
                            MetricRow(label: "COB", value: cobText, compact: true)
                        }

                        Divider()

                        // Proj / Upd
                        VStack(alignment: .leading, spacing: 4) {
                            MetricRow(label: "Proj", value: projectedText, compact: true)
                            MetricRow(label: "Upd", value: updatedText, compact: true)
                        }
                    }
                    .padding(.vertical, 2)
                }

            } compactLeading: {
                // MARK: Compact Leading (BG)
                Text(formatGlucoseShort(context.state.glucoseMmol))
                    .font(.caption)
                    .bold()
                    .monospacedDigit()

            } compactTrailing: {
                // MARK: Compact Trailing (trend)
                Text(trendText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            } minimal: {
                // MARK: Minimal (BG)
                Text(formatGlucoseMinimal(context.state.glucoseMmol))
                    .font(.caption2)
                    .bold()
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Small subview for label/value pairs

private struct MetricRow: View {
    let label: String
    let value: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 28 : 34, alignment: .leading)

            Text(value)
                .font(compact ? .caption : .subheadline)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

// MARK: - Formatting helpers (Widget-side)

private func formatGlucose(_ mmol: Double?) -> String {
    guard let mmol else { return "--" }
    return String(format: "%.1f", mmol)
}

private func formatIOB(_ iob: Double?) -> String {
    guard let iob else { return "--" }
    return String(format: "%.2f", iob)
}

private func formatCOB(_ cob: Double?) -> String {
    guard let cob else { return "--" }
    return String(format: "%.0f", cob)
}

private func formatTrend(_ trend: String?) -> String {
    let t = (trend ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? "—" : t
}

private func formatUpdatedTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale.current
    f.dateFormat = "h:mm a"
    return f.string(from: date)
}

private func formatGlucoseShort(_ mmol: Double?) -> String {
    guard let mmol else { return "--" }
    return String(format: "%.1f", mmol)
}

private func formatGlucoseMinimal(_ mmol: Double?) -> String {
    guard let mmol else { return "--" }
    return String(format: "%.1f", mmol)
}
