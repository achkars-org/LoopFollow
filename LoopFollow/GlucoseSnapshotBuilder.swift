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
        guard let raw = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .unknown }
    
        // Common Nightscout strings: "Flat", "FortyFiveUp", "SingleUp", "DoubleUp", "SingleDown", "DoubleDown"
        // Common variants: "rising", "falling", "rapidRise", "rapidFall"
        if raw.contains("doubleup") || raw.contains("rapidrise") || raw == "up2" || raw == "upfast" { return .upFast }
        if raw.contains("singleup") || raw.contains("fortyfiveup") || raw == "up" || raw == "up1" || raw == "rising" { return .up }
    
        if raw.contains("flat") || raw == "steady" || raw == "none" { return .flat }
    
        if raw.contains("doubledown") || raw.contains("rapidfall") || raw == "down2" || raw == "downfast" { return .downFast }
        if raw.contains("singledown") || raw.contains("fortyfivedown") || raw == "down" || raw == "down1" || raw == "falling" { return .down }
    
        return .unknown
    }
}