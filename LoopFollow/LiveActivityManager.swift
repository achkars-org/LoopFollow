//
//  LiveActivityManager.swift
//  LoopFollow
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
            let content = ActivityContent(
                state: initial,
                staleDate: Date().addingTimeInterval(15 * 60)
            )

            current = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            LogManager.shared.log(category: .general,
                                  message: "LiveActivity start error: \(error)")
        }
    }

    func update(glucoseText: String, trendText: String) {

        // 🔴 Critical for background silent push
        startIfNeeded()

        guard let activity = current else {
            LogManager.shared.log(category: .general,
                                  message: "⚠️ LiveActivityManager.update called but no current activity")
            return
        }

        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseText: glucoseText,
            trendText: trendText,
            updatedAt: Date()
        )

        Task {
            await activity.update(using: state)   // ✅ correct for your SDK
        }
    }
}
