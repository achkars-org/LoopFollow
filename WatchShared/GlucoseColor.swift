// LoopFollow
// GlucoseColor.swift

import SwiftUI

/// BG coloring shared by the Watch app and its complications.
enum GlucoseColor {
    private static let dynamicKey = "watch.dynamicBGColor"

    /// When on, BG is colored on a continuous hue ramp instead of three range colors.
    /// Stored in the Watch App Group so the complications follow the same choice.
    static var isDynamic: Bool {
        get { UserDefaults(suiteName: AppGroupID.current())?.bool(forKey: dynamicKey) ?? false }
        set { UserDefaults(suiteName: AppGroupID.current())?.set(newValue, forKey: dynamicKey) }
    }

    /// Red below the low line, orange above the high line, green in range — or the
    /// dynamic ramp when enabled. Lines come from the iPhone, synced into the App Group.
    static func color(forMgdl mgdl: Double, thresholds: (low: Double, high: Double) = LAAppGroupSettings.thresholdsMgdl()) -> Color {
        if isDynamic { return dynamic(forMgdl: mgdl) }
        if mgdl < thresholds.low { return .red }
        if mgdl > thresholds.high { return .orange }
        return .green
    }

    /// Hue ramp: red at 55 mg/dL and below, green at 100, purple at 220 and above.
    static func dynamic(forMgdl mgdl: Double) -> Color {
        let low = 55.0, target = 100.0, high = 220.0
        let red = 0.0, green = 120.0 / 360, purple = 270.0 / 360

        let hue: Double
        if mgdl <= low {
            hue = red
        } else if mgdl >= high {
            hue = purple
        } else if mgdl <= target {
            hue = red + (mgdl - low) / (target - low) * (green - red)
        } else {
            hue = green + (mgdl - target) / (high - target) * (purple - green)
        }
        return Color(hue: hue, saturation: 0.6, brightness: 0.9)
    }
}
