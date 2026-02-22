//
//  GlucoseLiveActivityAttributes 2.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-16.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//


import Foundation
import ActivityKit

struct GlucoseLiveActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {

        // Core glucose
        var glucoseMmol: Double?
        var previousGlucoseMmol: Double?
        var trend: String?

        // Treatments
        var iob: Double?
        var cob: Double?

        // Prediction
        var projectedMmol: Double?

        // Timestamp
        var updatedAt: Date
    }

    var title: String
}