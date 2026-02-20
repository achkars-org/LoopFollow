//
//  GlucoseLiveActivityWidget.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-12.
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

            // ✅ Delta (current - previous)
            let deltaText = formatDelta(
                current: context.state.glucoseMmol,
                previous: context.state.previousGlucoseMmol
            )

            let iobText = formatIOB(context.state.iob)
            let cobText = formatCOB(context.state.cob)
            let projectedText = formatGlucose(context.state.projectedMmol)
            let updatedText = formatUpdatedTime(context.state.updatedAt)

            // ✅ Colour code (red/yellow/green/gray)
            let statusColor = glucoseStatusColor(context.state.glucoseMmol)
            let bgTint = statusColor.opacity(0.15)

            VStack(alignment: .leading, spacing: 8) {

                Text(context.attributes.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // ✅ KEEP: the HStack remains
                HStack(alignment: .center, spacing: 12) {

                    // LEFT: BG + Trend + Delta
                    VStack(alignment: .leading, spacing: 2) {
                        Text(glucoseText)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .monospacedDigit()

                        HStack(spacing: 6) {
                            Text(trendText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if !deltaText.isEmpty {
                                Text(deltaText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
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

            // ✅ REMOVE the manually drawn rectangle:
            // .background(RoundedRectangle...)
            // .overlay(RoundedRectangle...)

            // Keep system-tint for Live Activity background if you like:
            .activityBackgroundTint(bgTint)
            .activitySystemActionForegroundColor(.primary)

        } dynamicIsland: { context in

            let glucoseText = formatGlucose(context.state.glucoseMmol)
            let trendText = formatTrend(context.state.trend)

            // ✅ Delta (current - previous)
            let deltaText = formatDelta(
                current: context.state.glucoseMmol,
                previous: context.state.previousGlucoseMmol
            )

            let iobText = formatIOB(context.state.iob)
            let cobText = formatCOB(context.state.cob)
            let projectedText = formatGlucose(context.state.projectedMmol)
            let updatedText = formatUpdatedTime(context.state.updatedAt)

            // ✅ Colour code
            let statusColor = glucoseStatusColor(context.state.glucoseMmol)
            let bgTint = statusColor.opacity(0.18)          // island background tint
            let keylineTint = statusColor.opacity(0.45)     // subtle outline tint

            return DynamicIsland {

                // MARK: Expanded
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {

                        HStack(alignment: .center, spacing: 10) {

                            // BG + Trend + Delta
                            VStack(alignment: .leading, spacing: 2) {
                                Text(glucoseText)
                                    .font(.title2)
                                    .bold()
                                    .monospacedDigit()

                                HStack(spacing: 6) {
                                    Text(trendText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if !deltaText.isEmpty {
                                        Text(deltaText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
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
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)

                    // ✅ REMOVE the manually drawn rectangle in expanded island too:
                    // .background(RoundedRectangle...)
                    // .overlay(RoundedRectangle...)
                }

            } compactLeading: {

                Text(formatGlucoseShort(context.state.glucoseMmol))
                    .font(.caption)
                    .bold()
                    .monospacedDigit()

            } compactTrailing: {

                Text(trendText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            } minimal: {

                Text(formatGlucoseMinimal(context.state.glucoseMmol))
                    .font(.caption2)
                    .bold()
                    .monospacedDigit()
            }
            // ✅ Add Dynamic Island tint (this is the “real” island tint)
            .keylineTint(keylineTint)
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

// MARK: - Formatting helpers

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

// ✅ Delta formatting: shows +0.3 / −0.2 etc (mmol)
private func formatDelta(current: Double?, previous: Double?) -> String {
    guard let current, let previous else { return "" }
    let d = current - previous
    if abs(d) < 0.05 { return "0.0" } // tiny noise
    return String(format: "%+.1f", d)
}

// MARK: - Colour code

/// Red = low, Yellow = high, Green = in-range, Gray = unknown.
/// Defaults: low < 3.9 mmol/L, high > 10.0 mmol/L
private func glucoseStatusColor(_ mmol: Double?) -> Color {
    guard let mmol else { return .gray }

    let lowThreshold = 3.9
    let highThreshold = 10.0

    if mmol < lowThreshold { return .red }
    if mmol > highThreshold { return .yellow }
    return .green
}
