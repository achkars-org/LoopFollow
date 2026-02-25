//
//  LoopFollowLiveActivity.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-24.
//

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct LoopFollowLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseLiveActivityAttributes.self) { context in
            // LOCK SCREEN / BANNER UI
            LockScreenLiveActivityView(state: context.state)
                .activitySystemActionForegroundColor(.white)
                .activityBackgroundTint(LAColors.backgroundTint(for: context.state.snapshot))
        } dynamicIsland: { context in
            // DYNAMIC ISLAND UI
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DynamicIslandLeadingView(snapshot: context.state.snapshot)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DynamicIslandTrailingView(snapshot: context.state.snapshot)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandBottomView(snapshot: context.state.snapshot)
                }
            } compactLeading: {
                DynamicIslandCompactLeadingView(snapshot: context.state.snapshot)
            } compactTrailing: {
                DynamicIslandCompactTrailingView(snapshot: context.state.snapshot)
            } minimal: {
                DynamicIslandMinimalView(snapshot: context.state.snapshot)
            }
            .keylineTint(LAColors.keyline(for: context.state.snapshot))
        }
    }
}

// MARK: - Lock Screen Contract View

@available(iOS 16.1, *)
private struct LockScreenLiveActivityView: View {

    let state: GlucoseLiveActivityAttributes.ContentState

    var body: some View {
        let s = state.snapshot

        HStack(spacing: 14) {

            // LEFT: Dominant glucose block
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LAFormat.glucose(s))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(LAFormat.trendArrow(s))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.top, 4)
                }

                Text(LAFormat.delta(s))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1)
                .padding(.vertical, 6)

            // RIGHT: 2×2 metrics grid (IOB/COB | Proj/Upd)
            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    MetricBlock(label: "IOB", value: LAFormat.iob(s))
                    MetricBlock(label: "COB", value: LAFormat.cob(s))
                }
                HStack(spacing: 18) {
                    MetricBlock(label: "Proj", value: LAFormat.projected(s))
                    MetricBlock(label: "Upd", value: LAFormat.updated(s))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MetricBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 58, alignment: .leading)
    }
}

// MARK: - Dynamic Island

@available(iOS 16.1, *)
private struct DynamicIslandLeadingView: View {
    let snapshot: GlucoseSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LAFormat.glucose(snapshot))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(LAFormat.delta(snapshot))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

@available(iOS 16.1, *)
private struct DynamicIslandTrailingView: View {
    let snapshot: GlucoseSnapshot
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(LAFormat.trendArrow(snapshot))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
            Text(LAFormat.updated(snapshot))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

@available(iOS 16.1, *)
private struct DynamicIslandBottomView: View {
    let snapshot: GlucoseSnapshot
    var body: some View {
        HStack(spacing: 14) {
            Text("IOB \(LAFormat.iob(snapshot))")
            Text("COB \(LAFormat.cob(snapshot))")
            Text("Proj \(LAFormat.projected(snapshot))")
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.92))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

@available(iOS 16.1, *)
private struct DynamicIslandCompactLeadingView: View {
    let snapshot: GlucoseSnapshot
    var body: some View {
        Text(LAFormat.glucose(snapshot))
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}

@available(iOS 16.1, *)
private struct DynamicIslandCompactTrailingView: View {
    let snapshot: GlucoseSnapshot
    var body: some View {
        Text(LAFormat.trendArrow(snapshot))
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
    }
}

@available(iOS 16.1, *)
private struct DynamicIslandMinimalView: View {
    let snapshot: GlucoseSnapshot
    var body: some View {
        Text(LAFormat.glucose(snapshot))
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}

// MARK: - Formatting

private enum LAFormat {

    static func glucose(_ s: GlucoseSnapshot) -> String {
        switch s.unit {
        case .mgdl:
            return String(Int(round(s.glucose)))
        case .mmol:
            return String(format: "%.1f", s.glucose)
        }
    }

    static func delta(_ s: GlucoseSnapshot) -> String {
        let d = s.delta
        // Show sign; if effectively zero, show +0 / 0 with unit-consistent precision.
        switch s.unit {
        case .mgdl:
            let v = Int(round(d))
            return v >= 0 ? "+\(v)" : "\(v)"
        case .mmol:
            let rounded = (abs(d) < 0.05) ? 0.0 : d
            return rounded >= 0 ? String(format: "+%.1f", rounded) : String(format: "%.1f", rounded)
        }
    }

    static func trendArrow(_ s: GlucoseSnapshot) -> String {
        switch s.trend {
        case .upFast: return "↑↑"
        case .up: return "↑"
        case .flat: return "→"
        case .down: return "↓"
        case .downFast: return "↓↓"
        case .unknown: return "–"
        }
    }

    static func iob(_ s: GlucoseSnapshot) -> String {
        guard let v = s.iob else { return "—" }
        return String(format: "%.1f", v)
    }

    static func cob(_ s: GlucoseSnapshot) -> String {
        guard let v = s.cob else { return "—" }
        return String(format: "%.0f", v)
    }

    static func projected(_ s: GlucoseSnapshot) -> String {
        guard let v = s.projected else { return "—" }
        switch s.unit {
        case .mgdl:
            return String(Int(round(v)))
        case .mmol:
            return String(format: "%.1f", v)
        }
    }

    static func updated(_ s: GlucoseSnapshot) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(s.updatedAt) / 60))
        return "\(minutes)m"
    }
}

// MARK: - Threshold-driven colors (Option A)

private enum LAColors {

    /// Uses Storage.shared.lowLine/highLine (mg/dL) for threshold comparison.
    /// Snapshot may be mg/dL or mmol; we compare in mg/dL by converting if needed.
    static func backgroundTint(for snapshot: GlucoseSnapshot) -> Color {
        let mgdl = toMgdl(snapshot)
        let low = Storage.shared.lowLine.value
        let high = Storage.shared.highLine.value

        if mgdl < low {
            return Color(uiColor: UIColor.systemRed).opacity(0.55)
        } else if mgdl > high {
            return Color(uiColor: UIColor.systemOrange).opacity(0.55)
        } else {
            return Color(uiColor: UIColor.systemGreen).opacity(0.50)
        }
    }

    static func keyline(for snapshot: GlucoseSnapshot) -> Color {
        let mgdl = toMgdl(snapshot)
        let low = Storage.shared.lowLine.value
        let high = Storage.shared.highLine.value

        if mgdl < low {
            return Color(uiColor: UIColor.systemRed)
        } else if mgdl > high {
            return Color(uiColor: UIColor.systemOrange)
        } else {
            return Color(uiColor: UIColor.systemGreen)
        }
    }

    private static func toMgdl(_ snapshot: GlucoseSnapshot) -> Double {
        switch snapshot.unit {
        case .mgdl:
            return snapshot.glucose
        case .mmol:
            // Convert mmol/L -> mg/dL for threshold comparison
            return GlucoseUnitConversion.convertGlucose(snapshot.glucose, from: .mmol, to: .mgdl)
        }
    }
}

// MARK: - Bundle entry

@available(iOS 16.1, *)
@main
struct LoopFollowWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LoopFollowLiveActivityWidget()
    }
}