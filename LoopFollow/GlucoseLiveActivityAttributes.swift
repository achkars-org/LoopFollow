//
//  GlucoseLiveActivityAttributes.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-12.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation
import ActivityKit

struct GlucoseLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var glucoseText: String
        var trendText: String
        var updatedAt: Date
    }

    var title: String
}
