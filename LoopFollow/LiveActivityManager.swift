// LiveActivityManager.swift
// Philippe Achkar
// 2026-03-05

import ActivityKit
import Foundation
import os

/// Live Activity manager for LoopFollow.
///
/// Contract:
/// - Does NOT know about Nightscout vs Dexcom.
/// - Consumes a GlucoseSnapshot already built by GlucoseSnapshotBuilder.
/// - Does NOT hardcode thresholds or colors.
/// - Safe to call from foreground or background refresh completions.
///
/// Update flow:
/// - refreshFromCurrentState(reason:) is the single public entry point.
/// - A 3-second debounce coalesces BG + DeviceStatus calls into one update.
/// - The actual ActivityKit update is wrapped in performExpiringActivity
///   to ensure delivery when the app is backgrounded.
/// - All ActivityKit calls are serialized via a cancellable Task.
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    // MARK: - Private State

    private(set) var current: Activity<GlucoseLiveActivityAttributes>?

    /// Observes activity lifecycle (ended / dismissed).
    private var stateObserverTask: Task<Void, Never>?

    /// Coalesces rapid successive refresh calls into a single update.
    private var debounceTask: Task<Void, Never>?

    /// Serializes ActivityKit update calls — only the latest wins.
    private var updateTask: Task<Void, Never>?

    /// Monotonic sequence for debugging and hung-update detection.
    private var seq: Int = 0

    // MARK: - Configuration

    private let debounceInterval: TimeInterval = 5.0
    private let staleDateInterval: TimeInterval = 15 * 60

    // MARK: - Public API

    /// The single entry point for all refresh triggers.
    ///
    /// Call this from:
    /// - viewUpdateNSBG (after all Storage writes are complete)
    /// - updateDeviceStatusDisplay (after markDataLoaded)
    /// - AppDelegate.didFinishLaunchingWithOptions
    /// - AppDelegate.applicationDidBecomeActive
    ///
    /// A 3-second debounce window coalesces BG + DeviceStatus calls
    /// that arrive close together into a single ActivityKit update.
    func refreshFromCurrentState(reason: String) {
        debounceTask?.cancel()

        debounceTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            } catch {
                // Task was cancelled — a newer refresh call arrived. Exit silently.
                return
            }

            guard !Task.isCancelled else { return }

            self.performRefresh(reason: reason)
        }
    }

    /// Ends the current Live Activity.
    func end(dismissalPolicy: ActivityUIDismissalPolicy = .default) {
        debounceTask?.cancel()
        debounceTask = nil
        updateTask?.cancel()
        updateTask = nil

        guard let activity = current else { return }

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
                seq: seq,
                reason: "end",
                producedAt: Date()
            )

            let content = ActivityContent(
                state: finalState,
                staleDate: nil
            )

            await activity.end(content, dismissalPolicy: dismissalPolicy)

            LogManager.shared.log(
                category: .general,
                message: "LA ended id=\(activity.id)",
                isDebug: true
            )

            if current?.id == activity.id {
                current = nil
            }
        }
    }

    // MARK: - Core Refresh (Post-Debounce)

    /// Executes after the debounce window closes.
    /// Builds the snapshot, persists it, then submits the ActivityKit update.
    private func performRefresh(reason: String) {
        let provider = StorageCurrentGlucoseStateProvider()

        guard let snapshot = GlucoseSnapshotBuilder.build(from: provider) else {
            LogManager.shared.log(
                category: .general,
                message: "LA refresh skipped (no snapshot) reason=\(reason)",
                isDebug: true
            )
            return
        }

        // Deduplicate: skip if snapshot is unchanged since last update.
        if let previous = GlucoseSnapshotStore.shared.load(), previous == snapshot {
            LogManager.shared.log(
                category: .general,
                message: "LA refresh skipped (unchanged snapshot) reason=\(reason)",
                isDebug: true
            )
            return
        }

        // Persist thresholds for extension coloring.
        LAAppGroupSettings.setThresholds(
            lowMgdl: Storage.shared.lowLine.value,
            highMgdl: Storage.shared.highLine.value
        )

        // Persist snapshot for extension reload and future Watch / CarPlay.
        GlucoseSnapshotStore.shared.save(snapshot)

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.log(
                category: .general,
                message: "LA not authorized (snapshot saved) reason=\(reason)",
                isDebug: true
            )
            return
        }

        startIfNeeded()
        submitUpdate(snapshot: snapshot, reason: reason)
    }

    // MARK: - Activity Lifecycle

    private func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            bind(to: existing, logReason: "reuse")
            return
        }

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

            let content = ActivityContent(
                state: initialState,
                staleDate: Date().addingTimeInterval(staleDateInterval)
            )

            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )

            bind(to: activity, logReason: "start-new")

            LogManager.shared.log(
                category: .general,
                message: "LA started id=\(activity.id)",
                isDebug: true
            )
        } catch {
            LogManager.shared.log(
                category: .general,
                message: "LA failed to start: \(error)",
                isDebug: true
            )
        }
    }

    // MARK: - Update Submission

    private func submitUpdate(snapshot: GlucoseSnapshot, reason: String) {
        // Rebind if we lost our reference (e.g. app relaunched).
        if current == nil, let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            bind(to: existing, logReason: "rebind")
        }

        guard let activity = current else {
            LogManager.shared.log(
                category: .general,
                message: "LA update skipped (no activity) reason=\(reason)",
                isDebug: true
            )
            return
        }

        // Cancel any in-flight update — latest snapshot wins.
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

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleDateInterval)
        )

        updateTask = Task { [weak self] in
            guard let self else { return }

            // Guard against updating an already-ended activity.
            if activity.activityState == .ended || activity.activityState == .dismissed {
                LogManager.shared.log(
                    category: .general,
                    message: "LA update skipped (activity not active) id=\(activityID) reason=\(reason)",
                    isDebug: true
                )
                if self.current?.id == activityID { self.current = nil }
                return
            }

            if Task.isCancelled { return }

            // Wrap in performExpiringActivity to ensure delivery when backgrounded.
            // OSAllocatedUnfairLock guarantees continuation.resume() is called exactly once,
            // even if the expiry callback fires concurrently with the update completing.
            await withCheckedContinuation { continuation in
                let hasResumed = OSAllocatedUnfairLock(initialState: false)

                ProcessInfo.processInfo.performExpiringActivity(
                    withReason: "LiveActivity.update"
                ) { expired in
                    if expired {
                        let alreadyDone = hasResumed.withLock { state -> Bool in
                            if state { return true }
                            state = true
                            return false
                        }
                        if !alreadyDone {
                            LogManager.shared.log(
                                category: .general,
                                message: "LA background time expired id=\(activityID) seq=\(nextSeq)",
                                isDebug: true
                            )
                            continuation.resume()
                        }
                        return
                    }

                    Task {
                        await activity.update(content)
                        let alreadyDone = hasResumed.withLock { state -> Bool in
                            if state { return true }
                            state = true
                            return false
                        }
                        if !alreadyDone {
                            continuation.resume()
                        }
                    }
                }
            }

            if Task.isCancelled { return }
            guard self.current?.id == activityID else { return }

            LogManager.shared.log(
                category: .general,
                message: "LA updated id=\(activityID) seq=\(nextSeq) reason=\(reason)",
                isDebug: true
            )
        }
    }

    // MARK: - Binding and Lifecycle Observation

    private func bind(to activity: Activity<GlucoseLiveActivityAttributes>, logReason: String) {
        if current?.id == activity.id { return }

        current = activity
        attachStateObserver(to: activity)

        LogManager.shared.log(
            category: .general,
            message: "LA bound id=\(activity.id) (\(logReason))",
            isDebug: true
        )
    }

    private func attachStateObserver(to activity: Activity<GlucoseLiveActivityAttributes>) {
        stateObserverTask?.cancel()
        stateObserverTask = Task {
            for await state in activity.activityStateUpdates {
                LogManager.shared.log(
                    category: .general,
                    message: "LA state id=\(activity.id) -> \(state)",
                    isDebug: true
                )
                if state == .ended || state == .dismissed {
                    if current?.id == activity.id {
                        current = nil
                        LogManager.shared.log(
                            category: .general,
                            message: "LA cleared current id=\(activity.id)",
                            isDebug: true
                        )
                    }
                }
            }
        }
    }
}