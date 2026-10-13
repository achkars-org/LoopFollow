// LoopFollow
// GlucoseColor.swift

import SwiftUI

/// BG coloring shared by the Watch app and its complications.
enum GlucoseColor {
    /// Red below the low line, orange above the high line, green in range.
    /// Lines come from the iPhone, synced into the Watch App Group.
    static func color(forMgdl mgdl: Double, thresholds: (low: Double, high: Double) = LAAppGroupSettings.thresholdsMgdl()) -> Color {
        if mgdl < thresholds.low { return .red }
        if mgdl > thresholds.high { return .orange }
        return .green
    }
}
