//
//  GlucoseSnapshotBuilder.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-24.
//

import Foundation

/// Provides the *latest* glucose-relevant values from LoopFollow’s single source of truth.
/// This is intentionally provider-agnostic (Nightscout vs Dexcom doesn’t matter).
protocol CurrentGlucoseStateProviding {
    /// Canonical glucose value in mg/dL (recommended internal canonical form).
    var glucoseMgdl: Double? { get }

    /// Canonical delta in mg/dL.
    var deltaMgdl: Double? { get }

    /// Canonical projected glucose in mg/dL.
    var projectedMgdl: Double? { get }

    /// Timestamp of the last reading/update.
    var updatedAt: Date? { get }

    /// Trend string / code from LoopFollow (we map to GlucoseSnapshot.Trend).
    var trendCode: String? { get }

    /// Secondary metrics (typically already unitless)
    var iob: Double? { get }
    var cob: Double? { get }
}

/// Builds a GlucoseSnapshot in the user’s preferred unit, without embedding provider logic.
enum GlucoseSnapshotBuilder {

        guard
            let glucoseMgdl = provider.glucoseMgdl,
            glucoseMgdl > 0,
            let updatedAt = provider.updatedAt
        else {
            return nil
        }

        let preferredUnit = PreferredGlucoseUnit.snapshotUnit()

        let glucose = GlucoseUnitConversion.convertGlucose(glucoseMgdl, from: .mgdl, to: preferredUnit)

        let deltaMgdl = provider.deltaMgdl ?? 0.0
        let delta = GlucoseUnitConversion.convertGlucose(deltaMgdl, from: .mgdl, to: preferredUnit)

        let projected: Double?
        if let projMgdl = provider.projectedMgdl {
            projected = GlucoseUnitConversion.convertGlucose(projMgdl, from: .mgdl, to: preferredUnit)
        } else {
            projected = nil
        }

        let trend = mapTrend(provider.trendCode)

        return GlucoseSnapshot(
            glucose: glucose,
            delta: delta,
            trend: trend,
            updatedAt: updatedAt,
            iob: provider.iob,
            cob: provider.cob,
            projected: projected,
            unit: preferredUnit
        )
    }

    private static func mapTrend(_ code: String?) -> GlucoseSnapshot.Trend {
        guard let code = code?.lowercased() else { return .unknown }

        // These mappings are intentionally conservative.
        // We’ll align them to LoopFollow’s exact trend representation once you show me the source-of-truth values.
        switch code {
        case "up", "singleup", "up1":
            return .up
        case "doubleup", "up2", "upfast":
            return .upFast
        case "flat", "steady":
            return .flat
        case "down", "singledown", "down1":
            return .down
        case "doubledown", "down2", "downfast":
            return .downFast
        default:
            return .unknown
        }
    }
}