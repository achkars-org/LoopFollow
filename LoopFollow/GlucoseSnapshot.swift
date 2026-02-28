//
//  GlucoseSnapshot.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-24.
//

import Foundation

/// Canonical, source-agnostic glucose state used by
/// Live Activity, future Watch complication, and CarPlay.
///
/// IMPORTANT:
/// - Contains raw numeric values only.
/// - Contains no formatting logic.
/// - Contains no threshold logic.
/// - Contains no provider-specific logic.
/// - All display formatting happens at render time.
/// - All color decisions happen via GlucoseColorResolver.
///
struct GlucoseSnapshot: Codable, Equatable, Hashable {

    // MARK: - Units

    enum Unit: String, Codable, Hashable {
        case mgdl
        case mmol
    }

    // MARK: - Core Glucose

    /// Raw glucose value in the user-selected unit.
    let glucose: Double

    /// Raw delta in the user-selected unit. May be 0.0 if unchanged.
    let delta: Double

    /// Trend direction (mapped from LoopFollow state).
    let trend: Trend

    /// Timestamp of reading.
    let updatedAt: Date

    // MARK: - Secondary Metrics

    /// Insulin On Board
    let iob: Double?

    /// Carbs On Board
    let cob: Double?

    /// Projected glucose (if available)
    let projected: Double?

    // MARK: - Unit Context

    /// Unit selected by the user in LoopFollow settings.
    let unit: Unit

    // MARK: - Derived Convenience

    /// Age of reading in seconds.
    var age: TimeInterval {
        Date().timeIntervalSince(updatedAt)
    }
}


// MARK: - Trend

extension GlucoseSnapshot {

    enum Trend: String, Codable, Hashable {
        case up
        case upFast
        case flat
        case down
        case downFast
        case unknown
    }
}