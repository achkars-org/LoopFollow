import Foundation
import ActivityKit

final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private(set) var current: Activity<GlucoseLiveActivityAttributes>?

    // MARK: - Start / Reuse

    func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.log(category: .liveactivities, message: "[LA] not authorized")
            return
        }

        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            current = existing
            LogManager.shared.log(category: .liveactivities, message: "[LA] reuse id=\(existing.id)")
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
            LogManager.shared.log(category: .liveactivities, message: "[LA] started id=\(activity.id)")
        } catch {
            LogManager.shared.log(category: .liveactivities, message: "[LA] start error: \(error)")
        }
    }

    // MARK: - Refresh

    func refreshFromCurrentState() async {
        startIfNeeded()

        guard let activity = Activity<GlucoseLiveActivityAttributes>.activities.first else {
            LogManager.shared.log(category: .liveactivities, message: "[LA] refresh: no active activity")
            return
        }
        current = activity

        // Snapshot storage
        let glucose = Storage.shared.currentGlucoseMmol.value
        let previous = Storage.shared.previousGlucoseMmol.value
        let trend = Storage.shared.trendArrow.value
        let iobFresh = Storage.shared.latestIOB.value
        let cobFresh = Storage.shared.latestCOB.value
        let projected = Storage.shared.projectedMmol.value

        // Keep last-known IOB/COB if this refresh didn't provide new values
        let cachedIOB = LAStateCache.loadIOB()
        let cachedCOB = LAStateCache.loadCOB()
        let mergedIOB = iobFresh ?? cachedIOB
        let mergedCOB = cobFresh ?? cachedCOB
        LAStateCache.save(iob: mergedIOB, cob: mergedCOB)

        if iobFresh == nil || cobFresh == nil {
            LogManager.shared.log(
                category: .liveactivities,
                message: "[LA] merge used cache iobFreshMissing=\(iobFresh == nil) cobFreshMissing=\(cobFresh == nil)"
            )
        }

        let state = GlucoseLiveActivityAttributes.ContentState(
            glucoseMmol: glucose,
            previousGlucoseMmol: previous,
            trend: trend,
            iob: mergedIOB,
            cob: mergedCOB,
            projectedMmol: projected,
            updatedAt: Date()
        )

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(15 * 60)
        )

        await activity.update(content)

        LogManager.shared.log(
            category: .liveactivities,
            message: "[LA] updated id=\(activity.id) glucose=\(glucose.map { String(format: "%.1f", $0) } ?? "nil") trend=\(trend ?? "nil") iob=\(mergedIOB.map { String(format: "%.2f", $0) } ?? "nil") cob=\(mergedCOB.map { String(format: "%.0f", $0) } ?? "nil") proj=\(projected.map { String(format: "%.1f", $0) } ?? "nil")"
        )
    }

    // MARK: - End

    func end() {
        guard let activity = Activity<GlucoseLiveActivityAttributes>.activities.first else { return }
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

        let finalContent = ActivityContent(state: finalState, staleDate: nil)

        let id = activity.id

        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
            LogManager.shared.log(category: .liveactivities, message: "[LA] ended id=\(id)")
        }
    }

    // MARK: - Debug

    #if DEBUG
    func debugForceUpdate() async {
        startIfNeeded()

        guard let activity = Activity<GlucoseLiveActivityAttributes>.activities.first else {
            LogManager.shared.log(category: .liveactivities, message: "[LA] debugForceUpdate: no active activity")
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
        LogManager.shared.log(category: .liveactivities, message: "[LA] debugForceUpdate updated id=\(activity.id)")
    }
    #endif
}
