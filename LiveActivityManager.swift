//
//  LiveActivityManager.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-24.
//

import Foundation
import ActivityKit
import UIKit

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
            LogManager.shared.log(category: .debug, message: "Live Activity not authorized")
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

            let seedSnapshot = GlucoseSnapshotStore.shared.load() ?? GlucoseSnapshot(
                glucose: 0,
                delta: 0,
                trend: .unknown,
                updatedAt: Date(),
                iob: nil,
                cob: nil,
                projected: nil,
                unit: .mgdl
            )

            let initialState = GlucoseLiveActivityAttributes.ContentState(
                snapshot: seedSnapshot,
                seq: 0,
                reason: "start",
                producedAt: Date()
            )

            let content = ActivityContent(state: initialState, staleDate: nil)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)

            bind(to: activity, logReason: "start-new")
            LogManager.shared.log(category: .debug, message: "Live Activity started id=\(activity.id)")
        } catch {
            LogManager.shared.log(category: .debug, message: "Live Activity failed to start: \(error)")
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
        LFUnifiedLog.debug("=== LoopFollow beacon: viewDidLoad ===")
        
        let groupID = AppGroupID.current()
        let ud = UserDefaults(suiteName: groupID)

        LogManager.shared.log(category: .debug, message: "[LA HB] app groupID=\(groupID) udNil=\(ud == nil) reason=\(reason)")

        LAHeartbeatStore.shared.setNow()

        if let hb = LAHeartbeatStore.shared.get() {
            LogManager.shared.log(category: .debug, message: "[LA HB] app readback hb=\(hb)")
        } else {
            LogManager.shared.log(category: .debug, message: "[LA HB] app readback hb=nil")
        }
        
        let provider = StorageCurrentGlucoseStateProvider()
    
        guard let snapshot = GlucoseSnapshotBuilder.build(from: provider) else {
            LogManager.shared.log(
                category: .debug,
                message: "LA refresh skipped (no snapshot) reason=\(reason)"
            )
            return
        }

        let fingerprint =
            "g=\(snapshot.glucose) d=\(snapshot.delta) t=\(snapshot.trend.rawValue) " +
            "at=\(snapshot.updatedAt.timeIntervalSince1970) iob=\(snapshot.iob?.description ?? "nil") " +
            "cob=\(snapshot.cob?.description ?? "nil") proj=\(snapshot.projected?.description ?? "nil") u=\(snapshot.unit.rawValue)"

        LogManager.shared.log(category: .debug, message: "[LA] snapshot \(fingerprint) reason=\(reason)")
        
        // Dedupe: if nothing changed compared to the last persisted snapshot, skip the ActivityKit update.
        // This reduces update spam and lowers the chance of “hung” update behavior.
        if let previous = GlucoseSnapshotStore.shared.load(), previous == snapshot {
            LogManager.shared.log(
                category: .debug,
                message: "LA refresh skipped (unchanged snapshot) reason=\(reason)"
            )
            
            return
        }
    
        // Persist thresholds for widget coloring (Option A).
        LAAppGroupSettings.setThresholds(
            lowMgdl: Storage.shared.lowLine.value,
            highMgdl: Storage.shared.highLine.value
        )
        
        // Persist for extension surfaces (Live Activity / future Watch / future CarPlay)
        GlucoseSnapshotStore.shared.save(snapshot)
    
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.log(
                category: .debug,
                message: "LA not authorized (snapshot saved) reason=\(reason)"
            )
            return
        }
    
        // Always attempt to update if one exists.
        // Only start a new activity when app is visible.
        if current == nil, let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            bind(to: existing, logReason: "bind-existing")
        }

        if let _ = current {
            update(snapshot: snapshot, reason: reason)
            return
        }

        // No activity exists yet — only start if the app is currently visible.
        if isAppVisibleForLiveActivityStart() {
            startIfNeeded()
            if current != nil {
                update(snapshot: snapshot, reason: reason)
            }
        } else {
            LogManager.shared.log(category: .debug, message: "LA start suppressed (not visible) reason=\(reason)")
        }
    }

    private func isAppVisibleForLiveActivityStart() -> Bool {
        // “Visibility” errors happen when trying to start from background.
        // We only start when there’s at least one foreground-active scene.
        let scenes = UIApplication.shared.connectedScenes
        return scenes.contains { $0.activationState == .foregroundActive }
    }
    
    /// Updates the Live Activity content. Safe to call repeatedly; only latest update is applied.
    func update(snapshot: GlucoseSnapshot, reason: String) {
        // Bind to an existing activity if we lost our reference (e.g. app relaunched)
        if current == nil, let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            bind(to: existing, logReason: "bind-existing")
        }
    
        guard let activity = current else {
            LogManager.shared.log(
                category: .debug,
                message: "LA update skipped (no activity) reason=\(reason)"
            )
            return
        }
    
        // Cancel any in-flight update and apply only the latest
        updateTask?.cancel()
    
        seq += 1
        let nextSeq = seq
        let activityID = activity.id
    
        let state = GlucoseLiveActivityAttributes.ContentState(
            snapshot: snapshot,
            seq: nextSeq,
            reason: reason,
            producedAt: Date()
        )
    
        updateTask = Task { [weak self] in
            guard let self else { return }
    
            // If the activity ended/dismissed between scheduling and execution, bail.
            // (ActivityKit often no-ops, but we avoid noisy logs.)
            if activity.activityState == .ended || activity.activityState == .dismissed {
                LogManager.shared.log(
                    category: .debug,
                    message: "LA update skipped (activity not active) id=\(activityID) state=\(activity.activityState) reason=\(reason)"
                )
                if self.current?.id == activityID { self.current = nil }
                return
            }
    
            let content = ActivityContent(state: state, staleDate: nil)
    
            // iOS 16.1+ update is async; it may throw or be cancelled.
            // If this task was cancelled, do not log success.
            if Task.isCancelled { return }
    
            await activity.update(content)
    
            if Task.isCancelled { return }
    
            // If current has moved on to another activity, don't claim success for the old one.
            guard self.current?.id == activityID else { return }
    
            LogManager.shared.log(
                category: .debug,
                message: "LA updated id=\(activityID) seq=\(nextSeq) reason=\(reason)"
            )
        }
    }

    // MARK: - Binding / Lifecycle

    private func bind(to activity: Activity<GlucoseLiveActivityAttributes>, logReason: String) {
        if current?.id == activity.id { return }

        current = activity
        attachStateObserver(to: activity)

        LogManager.shared.log(category: .debug, message: "LA bound id=\(activity.id) (\(logReason))")
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
