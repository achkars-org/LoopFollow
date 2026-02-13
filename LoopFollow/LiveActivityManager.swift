//
//  LiveActivityManager.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-12.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation
import ActivityKit

final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private(set) var current: Activity<GlucoseLiveActivityAttributes>?

    func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            current = existing
            return
        }

        let attributes = GlucoseLiveActivityAttributes(title: "LoopFollow")
        let initial = GlucoseLiveActivityAttributes.ContentState(
            glucoseText: "--",
            trendText: "",
            updatedAt: Date()
        )

        do {
            current = try Activity.request(attributes: attributes,
                                           contentState: initial,
                                           pushType: nil)
        } catch {
            print("LiveActivity start error:", error)
        }
    }

    func update(glucoseText: String, trendText: String) {
        guard let a = current else { return }
        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseText: glucoseText,
            trendText: trendText,
            updatedAt: Date()
        )
        Task { await a.update(using: state) }
    }
}
