import Foundation
import ActivityKit

final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private(set) var current: Activity<GlucoseLiveActivityAttributes>?

    // MARK: - Start

    func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            current = existing
            return
        }

        let attributes = GlucoseLiveActivityAttributes(title: "LoopFollow")

        let initial = GlucoseLiveActivityAttributes.ContentState(
            glucoseMmol: nil,
            previousGlucoseMmol: nil,
            trend: nil,
            iob: nil,
            cob: nil,
            projectedMmol: nil,
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
            LogManager.shared.log(
                category: .general,
                message: "LiveActivity start error: \(error)"
            )
        }
    }

    // MARK: - Atomic Refresh

    func refreshFromCurrentState() {

        startIfNeeded()

        guard let activity = current else {
            LogManager.shared.log(
                category: .general,
                message: "⚠️ refreshFromCurrentState called but no activity"
            )
            return
        }

        // Pull everything from shared state (we will wire these next)
        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMmol: Storage.shared.currentGlucoseMmol.value,
            previousGlucoseMmol: Storage.shared.previousGlucoseMmol.value,
            trend: Storage.shared.trendArrow.value,
            iob: Storage.shared.latestIOB.value,
            cob: Storage.shared.latestCOB.value,
            projectedMmol: Storage.shared.projectedMmol.value,
            updatedAt: Date()
        )

        Task {
            await activity.update(using: state)
        }
    }
}
