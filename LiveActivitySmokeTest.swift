// LiveActivitySmokeTest.swift
// Philippe Achkar
// 2026-02-28

import Foundation
import ActivityKit

enum LiveActivitySmokeTest {

    /// Call this from AppDelegate or SceneDelegate to verify ActivityKit works.
    static func run(source: String) {

        LogManager.shared.log(category: .general, message: "[LA SmokeTest] run source=\(source)")
        LogManager.shared.log(category: .debug, message: "[LA SmokeTest] run source=\(source)")

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.log(category: .general,
                                  message: "[LA] SmokeTest blocked: Live Activities not enabled")
            return
        }

        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            LogManager.shared.log(category: .general,
                                  message: "[LA] SmokeTest found existing activity id=\(existing.id)")
            return
        }

        let snapshot = makeMinimalSnapshotForSmokeTest()

        let now = Date()
        let initialState = GlucoseLiveActivityAttributes.ContentState(
            snapshot: snapshot,
            seq: 1,
            reason: "SmokeTest",
            producedAt: now
        )

        let attributes = GlucoseLiveActivityAttributes(title: "LoopFollow")

        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"

        LogManager.shared.log(
            category: .general,
            message: "[LA SmokeTest] context bundleID=\(bundleID) os=\(osString) source=\(source)"
        )
        
        Task {
            if #available(iOS 16.1, *) {
                do {
                    let activity = try Activity.request(
                        attributes: attributes,
                        content: .init(
                            state: initialState,
                            staleDate: now.addingTimeInterval(15 * 60)
                        ),
                        pushType: nil
                    )

                    LogManager.shared.log(category: .general,
                                          message: "[LA] SmokeTest started id=\(activity.id)")
                } catch {
                    let bundleID = Bundle.main.bundleIdentifier ?? "nil"
                    LogManager.shared.log(category: .general,
                                          message: "[LA] SmokeTest FAILED bundleID=\(bundleID) error=\(error)")
                }
            } else {
                LogManager.shared.log(category: .general,
                                      message: "[LA] SmokeTest blocked: requires iOS 16.1+")
            }
        }
    }

    // MARK: - Minimal Snapshot

    private static func makeMinimalSnapshotForSmokeTest() -> GlucoseSnapshot {
        let now = Date()

        return GlucoseSnapshot(
            glucose: 6.0,
            delta: 0.0,
            trend: .flat,
            updatedAt: now,
            iob: nil,
            cob: nil,
            projected: nil,
            unit: .mmol
        )
    }
}
