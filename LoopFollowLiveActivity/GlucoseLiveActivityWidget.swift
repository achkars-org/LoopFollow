//
//  GlucoseLiveActivityWidget.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-12.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct GlucoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {

        ActivityConfiguration(for: GlucoseLiveActivityAttributes.self) { context in

            let glucoseText = formatGlucose(context.state.glucoseMmol)
            let trendText = context.state.trend ?? ""

            VStack(spacing: 6) {
                Text(context.attributes.title).font(.caption)

                HStack(spacing: 6) {
                    Text(glucoseText)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))

                    Text(trendText)
                        .font(.headline)
                }

                Text(context.state.updatedAt, style: .time)
                    .font(.caption2)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)

        } dynamicIsland: { context in

            let glucoseText = formatGlucose(context.state.glucoseMmol)
            let trendText = context.state.trend ?? ""

            return DynamicIsland {

                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 6) {
                        Text(glucoseText)
                            .font(.title2)
                            .bold()
                            .monospacedDigit()

                        Text(trendText)
                            .font(.headline)
                    }
                }

            } compactLeading: {
                Text(formatGlucoseShort(context.state.glucoseMmol))
                    .font(.caption)
                    .bold()
                    .monospacedDigit()

            } compactTrailing: {
                Text(trendText)
                    .font(.caption2)

            } minimal: {
                Text(formatGlucoseMinimal(context.state.glucoseMmol))
                    .font(.caption2)
                    .bold()
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Formatting helpers (Widget-side)

private func formatGlucose(_ mmol: Double?) -> String {
    guard let mmol else { return "--" }
    return String(format: "%.1f", mmol)
}

private func formatGlucoseShort(_ mmol: Double?) -> String {
    // Dynamic Island compactLeading: keep it short
    guard let mmol else { return "--" }
    return String(format: "%.1f", mmol)
}

private func formatGlucoseMinimal(_ mmol: Double?) -> String {
    // Minimal: show 2–3 chars if possible (e.g. "6.4" or "--")
    guard let mmol else { return "--" }
    return String(format: "%.1f", mmol)
}
