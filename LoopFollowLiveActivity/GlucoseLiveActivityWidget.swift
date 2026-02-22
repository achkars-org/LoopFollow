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

            // MARK: - Lock Screen UI

            let glucoseText = formatGlucose(context.state.glucoseMmol)
            let trendText = formatTrend(context.state.trend)

            // Delta (current - previous)
            let deltaText = formatDelta(
                current: context.state.glucoseMmol,
                previous: context.state.previousGlucoseMmol
            )

            let iobText = formatIOB(context.state.iob)
            let cobText = formatCOB(context.state.cob)
            let projectedText = formatGlucose(context.state.projectedMmol)
            let updatedText = formatUpdatedTime(context.state.updatedAt)

            // ✅ Colour code (severity-based background tint)
            let statusColor = glucoseStatusColor(context.state.glucoseMmol)
            let bgTint = statusColor.opacity(glucoseSeverityOpacity(context.state.glucoseMmol))

            // ✅ Accent used ONLY for BG + arrow
            let accent = statusColor.opacity(0.95)

            VStack(alignment: .leading, spacing: 8) {

                // ✅ Removed "LoopFollow" title line (was context.attributes.title)

                HStack(alignment: .center, spacing: 12) {

                    // LEFT: BG + Trend + Delta
                    VStack(alignment: .leading, spacing: 2) {

                        // ✅ BG number coloured
                        Text(glucoseText)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .monospacedDigit()

                        HStack(spacing: 6) {

                            // ✅ Arrow coloured
                            Text(trendText)
                                .font(.subheadline)


                            // ✅ Delta stays default colour (secondary)
                            if !deltaText.isEmpty {
                                Text(deltaText)
                                    .font(.subheadline)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(minWidth: 90, alignment: .leading)

                    Divider()

                    // MIDDLE: IOB / COB (default colours)
                    VStack(alignment: .leading, spacing: 6) {
                        MetricRow(label: "IOB", value: iobText)
                        MetricRow(label: "COB", value: cobText)
                    }
                    .frame(minWidth: 80, alignment: .leading)

                    Divider()

                    // RIGHT: Projected / Updated (default colours)
                    VStack(alignment: .leading, spacing: 6) {
                        MetricRow(label: "Proj", value: projectedText)
                        MetricRow(label: "Upd", value: updatedText)
                    }
                    .frame(minWidth: 80, alignment: .leading)
                }
                
                // DEBUG (temporary): shows whether updates are landing
                Text("seq \(context.state.seq) • \(context.state.debug) • \(context.state.updatedAtEpoch)")
                    .font(.caption2)
                    .monospacedDigit()
                    .opacity(0.55)
                    .lineLimit(1)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)

            // ✅ Keep severity-based background tint
            .activityBackgroundTint(bgTint)

            // ✅ Keep system action colour neutral
            .activitySystemActionForegroundColor(.primary)
            

            
        } dynamicIsland: { context in

            let glucoseText = formatGlucose(context.state.glucoseMmol)
            let trendText = formatTrend(context.state.trend)

            let deltaText = formatDelta(
                current: context.state.glucoseMmol,
                previous: context.state.previousGlucoseMmol
            )

            let iobText = formatIOB(context.state.iob)
            let cobText = formatCOB(context.state.cob)
            let projectedText = formatGlucose(context.state.projectedMmol)
            let updatedText = formatUpdatedTime(context.state.updatedAt)

            // Colour code (we’ll tint text + keep a keyline attempt)
            let statusColor = glucoseStatusColor(context.state.glucoseMmol)
            let accent = statusColor.opacity(0.95)
            let keylineTint = statusColor.opacity(0.95)

            return DynamicIsland {

                // MARK: - Expanded
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        HStack(alignment: .center, spacing: 10) {

                            // BG + Trend + Delta (tinted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(glucoseText)
                                    .font(.title2)
                                    .bold()
                                    .monospacedDigit()
                                    .foregroundStyle(accent)

                                HStack(spacing: 6) {
                                    Text(trendText)
                                        .font(.caption)
                                        .foregroundStyle(accent)

                                    if !deltaText.isEmpty {
                                        Text(deltaText)
                                            .font(.caption)
                                            .foregroundStyle(accent)
                                            .monospacedDigit()
                                    }
                                }
                            }

                            Divider()

                            // IOB / COB
                            VStack(alignment: .leading, spacing: 4) {
                                MetricRow(label: "IOB", value: iobText, compact: true, valueColor: .primary)
                                MetricRow(label: "COB", value: cobText, compact: true, valueColor: .primary)
                            }

                            Divider()

                            // Proj / Upd
                            VStack(alignment: .leading, spacing: 4) {
                                MetricRow(label: "Proj", value: projectedText, compact: true, valueColor: .primary)
                                MetricRow(label: "Upd", value: updatedText, compact: true, valueColor: .primary)
                            }
                        }
                        
                        Text("seq \(context.state.seq) • \(context.state.debug)")
                            .font(.caption2)
                            .monospacedDigit()
                            .opacity(0.55)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                }

            } compactLeading: {

                Text(formatGlucoseShort(context.state.glucoseMmol))
                    .font(.caption)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(accent)

            } compactTrailing: {

                Text(trendText)
                    .font(.caption2)
                    .foregroundStyle(accent)

            } minimal: {

                Text(formatGlucoseMinimal(context.state.glucoseMmol))
                    .font(.caption2)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
            .keylineTint(keylineTint)
        }
    }
}

// MARK: - Small subview for label/value pairs

private struct MetricRow: View {
    let label: String
    let value: String
    var compact: Bool = false
    var valueColor: Color = .primary

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
                .foregroundStyle(valueColor)
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

private func formatDelta(current: Double?, previous: Double?) -> String {
    guard let current, let previous else { return "" }
    let d = current - previous
    if abs(d) < 0.05 { return "0.0" }
    return String(format: "%+.1f", d)
}

// MARK: - Colour code (App Group-backed thresholds)

private let mgdlPerMmol: Double = 18.0182

private func readThresholdsMgdl() -> (low: Double, high: Double) {
    let appGroupID = "group.com.2HEY366Q6J.LoopFollow"
    guard let defaults = UserDefaults(suiteName: appGroupID) else {
        return (70.0, 180.0)
    }

    let low: Double = defaults.object(forKey: "la.lowLineMgdl") != nil
        ? defaults.double(forKey: "la.lowLineMgdl")
        : 70.0

    let high: Double = defaults.object(forKey: "la.highLineMgdl") != nil
        ? defaults.double(forKey: "la.highLineMgdl")
        : 180.0

    if high <= low { return (70.0, 180.0) }
    return (low, high)
}

private func glucoseStatusColor(_ mmol: Double?) -> Color {
    guard let mmol else { return .gray }
    let (lowMgdl, highMgdl) = readThresholdsMgdl()

    let mgdl = mmol * mgdlPerMmol
    if mgdl < lowMgdl { return .red }
    if mgdl > highMgdl { return .orange }
    return .green
}

private func glucoseSeverityOpacity(_ mmol: Double?) -> Double {
    guard let mmol else { return 0.18 }
    let (lowMgdl, highMgdl) = readThresholdsMgdl()

    let mgdl = mmol * mgdlPerMmol

    if mgdl >= lowMgdl && mgdl <= highMgdl {
        return 0.25
    }

    if mgdl < lowMgdl {
        let distance = min((lowMgdl - mgdl) / 40.0, 1.0)
        return 0.35 + (distance * 0.35) // up to ~0.70
    }

    let distance = min((mgdl - highMgdl) / 80.0, 1.0)
    return 0.30 + (distance * 0.30) // up to ~0.60
}
