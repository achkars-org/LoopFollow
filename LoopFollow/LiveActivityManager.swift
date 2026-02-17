import Foundation
import ActivityKit

final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private(set) var current: Activity<GlucoseLiveActivityAttributes>?

    // MARK: - Start

    func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.log(
                category: .general,
                message: "LiveActivity not authorized"
            )
            return
        }

        // Reuse existing if present
        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            current = existing
            LogManager.shared.log(
                category: .general,
                message: "LiveActivity reuse id=\(existing.id)"
            )
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

            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )

            current = activity

            LogManager.shared.log(
                category: .general,
                message: "LiveActivity started id=\(activity.id)"
            )

        } catch {
            LogManager.shared.log(
                category: .general,
                message: "LiveActivity start error: \(error)"
            )
        }
    }

    // MARK: - Atomic Refresh

    func refreshFromCurrentState() async {

        startIfNeeded()

        // Always grab the currently displayed activity
        guard let activity = Activity<GlucoseLiveActivityAttributes>.activities.first else {
            LogManager.shared.log(
                category: .general,
                message: "⚠️ refreshFromCurrentState: no active activity"
            )
            return
        }

        current = activity

        // Snapshot storage
        let glucose = Storage.shared.currentGlucoseMmol.value
        let previous = Storage.shared.previousGlucoseMmol.value
        let trend = Storage.shared.trendArrow.value
        let iob = Storage.shared.latestIOB.value
        let cob = Storage.shared.latestCOB.value
        let projected = Storage.shared.projectedMmol.value

        LogManager.shared.log(
            category: .general,
            message:
                """
                📌 [LA] id=\(activity.id)
                glucose=\(glucose.map { String(format: "%.1f", $0) } ?? "nil")
                prev=\(previous.map { String(format: "%.1f", $0) } ?? "nil")
                trend=\(trend ?? "nil")
                iob=\(iob.map { String(format: "%.2f", $0) } ?? "nil")
                cob=\(cob.map { String(format: "%.0f", $0) } ?? "nil")
                proj=\(projected.map { String(format: "%.1f", $0) } ?? "nil")
                """
        )

        
        // Load last known values
        let cachedIOB = LAStateCache.loadIOB()
        let cachedCOB = LAStateCache.loadCOB()

        // Merge logic: only overwrite if new values exist
        let mergedIOB = iob ?? cachedIOB
        let mergedCOB = cob ?? cachedCOB

        // Save only if fresh values exist
        LAStateCache.save(iob: iob, cob: cob)
        
        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMmol: glucose,
            previousGlucoseMmol: previous,
            trend: trend,
            iob: iob,
            cob: cob,
            projectedMmol: projected,
            updatedAt: Date()
        )

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(15 * 60)
        )

        // NOTE: update(_:) is async but does NOT throw.
        await activity.update(content)

        LogManager.shared.log(
            category: .general,
            message: "✅ LiveActivity updated id=\(activity.id)"
        )
    }

    // MARK: - Debug: Force a visible update

    func debugForceUpdate() async {
        startIfNeeded()

        guard let activity = Activity<GlucoseLiveActivityAttributes>.activities.first else {
            LogManager.shared.log(
                category: .general,
                message: "⚠️ debugForceUpdate: no active activity"
            )
            return
        }

        current = activity

        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMmol: 6.4,
            previousGlucoseMmol: 6.1,
            trend: "→",
            iob: 1.23,
            cob: 18,
            projectedMmol: 6.8,
            updatedAt: Date()
        )

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(15 * 60)
        )

        await activity.update(content)

        LogManager.shared.log(
            category: .general,
            message: "✅ debugForceUpdate updated id=\(activity.id)"
        )
    }

    // MARK: - End Activity (optional but useful for debugging)

    // MARK: - End Activity

    // MARK: - End Activity

    func end() {
        guard let activity = Activity<GlucoseLiveActivityAttributes>.activities.first else {
            return
        }

        current = activity

        let finalState = GlucoseLiveActivityAttributes.ContentState(
            glucoseMmol: Storage.shared.currentGlucoseMmol.value,
            previousGlucoseMmol: Storage.shared.previousGlucoseMmol.value,
            trend: Storage.shared.trendArrow.value,
            iob: Storage.shared.latestIOB.value,
            cob: Storage.shared.latestCOB.value,
            projectedMmol: Storage.shared.projectedMmol.value,
            updatedAt: Date()
        )

        let finalContent = ActivityContent(
            state: finalState,
            staleDate: nil
        )

        Task {
            await activity.end(
                finalContent,
                dismissalPolicy: .immediate
            )

            LogManager.shared.log(
                category: .general,
                message: "LiveActivity ended id=\(activity.id)"
            )
        }
    }
}
