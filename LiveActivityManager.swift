//
//  LiveActivityManager.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-24.
//

import Foundation
import ActivityKit

/// Live Activity manager for LoopFollow.
///
/// Contract:
/// - This manager does NOT know about Nightscout vs Dexcom.
/// - It consumes a GlucoseSnapshot (already unit-converted by the SnapshotBuilder).
/// - It does NOT hardcode thresholds or colors.
/// - It is safe to call from foreground or background refresh completions.
///
/// Notes:
/// - Uses a single in-flight Task to serialize updates.
/// - Observes activity lifecycle to avoid updating ended/dismissed activities.
@available(iOS 16.1, *)
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    // Bound activity (if any)
    private(set) var current: Activity<GlucoseLiveActivityAttributes>?

    // Observe lifecycle changes (ended/dismissed)
    private var stateObserverTask: Task<Void, Never>?

    // Serialize updates
    private var updateTask: Task<Void, Never>?

    // Monotonic sequence for debugging / “hung” detection in UI if desired
    private var seq: Int = 0

    // MARK: - Public API

    /// Ensures we are bound to an existing Live Activity if present,
    /// or creates a new one if none exists.
    func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.log(category: .general, message: "Live Activity not authorized", isDebug: true)
            return
        }

        // Reuse an existing activity if present
        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            bind(to: existing, logReason: "reuse")
            return
        }

        // Start a new activity
        do {
            let attributes = GlucoseLiveActivityAttributes(title: "LoopFollow")
            let initialState = GlucoseLiveActivityAttributes.ContentState(
                snapshot: GlucoseSnapshot(
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
                reason: "start",
                producedAt: Date()
            )

            let content = ActivityContent(state: initialState, staleDate: nil)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            bind(to: activity, logReason: "start-new")

            LogManager.shared.log(category: .general, message: "Live Activity started id=\(activity.id)", isDebug: true)
        } catch {
            LogManager.shared.log(category: .general, message: "Live Activity failed to start: \(error)", isDebug: true)
        }
    }

    /// Ends the current Live Activity (if any).
    func end(dismissalPolicy: ActivityUIDismissalPolicy = .default) {
        updateTask?.cancel()
        updateTask = nil

        guard let activity = current else { return }

        Task {
            let finalState = GlucoseLiveActivityAttributes.ContentState(
                snapshot: (GlucoseSnapshotStore.shared.load() ?? GlucoseSnapshot(
                    glucose: 0,
                    delta: 0,
                    trend: .unknown,
                    updatedAt: Date(),
                    iob: nil,
                    cob: nil,
                    projected: nil,
                    unit: .mgdl
                )),
                seq: seq,
                reason: "end",
                producedAt: Date()
            )

            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: dismissalPolicy)

            LogManager.shared.log(category: .general, message: "Live Activity ended id=\(activity.id)", isDebug: true)

            if current?.id == activity.id {
                current = nil
            }
        }
    }

    /// The main entrypoint you will call from LoopFollow’s workflow completion points:
    /// - BG pipeline completion (after BG processing commits raw fields)
    /// - DeviceStatus completion (after IOB/COB/Proj commits raw fields)
    ///
    /// This:
    /// 1) builds a GlucoseSnapshot from Storage-backed provider
    /// 2) persists it to App Group
    /// 3) starts activity if needed
    /// 4) updates activity content
    func refreshFromCurrentState(reason: String) {
        let provider = StorageCurrentGlucoseStateProvider()

        guard let snapshot = GlucoseSnapshotBuilder.build(from: provider) else {
            LogManager.shared.log(category: .general, message: "LA refresh skipped (no snapshot) reason=\(reason)", isDebug: true)
            return
        }

        // Persist for extension surfaces (Live Activity / future Watch / future CarPlay)
        GlucoseSnapshotStore.shared.save(snapshot)

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.log(category: .general, message: "LA not authorized (snapshot saved) reason=\(reason)", isDebug: true)
            return
        }

        // Ensure an activity exists & update it
        startIfNeeded()
        update(snapshot: snapshot, reason: reason)
    }

    // MARK: - Update

    /// Updates the Live Activity content. Safe to call repeatedly; only latest update is applied.
    func update(snapshot: GlucoseSnapshot, reason: String) {
        // Bind to an existing activity if we lost our reference (e.g. app relaunched)
        if current == nil, let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            bind(to: existing, logReason: "bind-existing")
        }

        guard let activity = current else {
            LogManager.shared.log(category: .general, message: "LA update skipped (no activity) reason=\(reason)", isDebug: true)
            return
        }

        // Cancel any in-flight update and apply only the latest
        updateTask?.cancel()

        seq += 1
        let nextSeq = seq

        let state = GlucoseLiveActivityAttributes.ContentState(
            snapshot: snapshot,
            seq: nextSeq,
            reason: reason,
            producedAt: Date()
        )

        updateTask = Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)

            LogManager.shared.log(
                category: .general,
                message: "LA updated id=\(activity.id) seq=\(nextSeq) reason=\(reason)",
                isDebug: true
            )
        }
    }

    // MARK: - Binding / Lifecycle

    private func bind(to activity: Activity<GlucoseLiveActivityAttributes>, logReason: String) {
        if current?.id == activity.id { return }

        current = activity
        attachStateObserver(to: activity)

        LogManager.shared.log(category: .general, message: "LA bound id=\(activity.id) (\(logReason))", isDebug: true)
    }

    private func attachStateObserver(to activity: Activity<GlucoseLiveActivityAttributes>) {
        stateObserverTask?.cancel()
        stateObserverTask = Task {
            for await state in activity.activityStateUpdates {
                LogManager.shared.log(category: .general, message: "LA state id=\(activity.id) -> \(state)", isDebug: true)
                if state == .ended || state == .dismissed {
                    if current?.id == activity.id {
                        current = nil
                        LogManager.shared.log(category: .general, message: "LA cleared current id=\(activity.id)", isDebug: true)
                    }
                }
            }
        }
    }
}