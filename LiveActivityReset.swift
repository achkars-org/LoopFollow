// LiveActivityReset.swift
// Philippe Achkar
// 2026-02-28

import Foundation
import ActivityKit

@available(iOS 16.1, *)
enum LiveActivityReset {

    static func endAll(reason: String) {
        let activities = Activity<GlucoseLiveActivityAttributes>.activities
        LogManager.shared.log(category: .debug, message: "[LA Reset] endAll reason=\(reason) count=\(activities.count)")

        for activity in activities {
            Task {
                let finalState = GlucoseLiveActivityAttributes.ContentState(
                    snapshot: GlucoseSnapshotStore.shared.load() ?? GlucoseSnapshot(
                        glucose: 0,
                        delta: 0,
                        trend: .unknown,
                        updatedAt: Date(),
                        iob: nil,
                        cob: nil,
                        projected: nil,
                        unit: .mgdl
                    ),
                    seq: 0,
                    reason: "reset",
                    producedAt: Date()
                )

                await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
                LogManager.shared.log(category: .debug, message: "[LA Reset] ended id=\(activity.id)")
            }
        }
    }
}
