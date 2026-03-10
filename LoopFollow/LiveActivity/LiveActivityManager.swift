// LiveActivityManager.swift
// Philippe Achkar
// 2026-03-07

import Foundation
@preconcurrency import ActivityKit
import UIKit
import os

/// Live Activity manager for LoopFollow.

@available(iOS 16.1, *)
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundAudioFailed),
            name: .backgroundAudioFailed,
            object: nil,
        )
    }

    /// Fires before the app loses focus (lock screen, home button, etc.).
    /// Cancels any pending debounced refresh and pushes the latest snapshot
    /// directly to the Live Activity while the app is still foreground-active,
    /// ensuring the LA is up to date the moment the lock screen appears.
    @objc private func handleWillResignActive() {
        guard Storage.shared.laEnabled.value, let activity = current else { return }

        refreshWorkItem?.cancel()
        refreshWorkItem = nil

        let provider = StorageCurrentGlucoseStateProvider()
        guard let snapshot = GlucoseSnapshotBuilder.build(from: provider) else { return }

        LAAppGroupSettings.setThresholds(
            lowMgdl: Storage.shared.lowLine.value,
            highMgdl: Storage.shared.highLine.value,
        )
        GlucoseSnapshotStore.shared.save(snapshot)

        seq += 1
        let nextSeq = seq
        let state = GlucoseLiveActivityAttributes.ContentState(
            snapshot: snapshot,
            seq: nextSeq,
            reason: "resign-active",
            producedAt: Date(),
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date(timeIntervalSince1970: Storage.shared.laRenewBy.value),
            relevanceScore: 100.0,
        )

        Task {
            // Direct ActivityKit update — app is still active at this point.
            await activity.update(content)
            LogManager.shared.log(category: .general, message: "[LA] resign-active flush sent seq=\(nextSeq)", isDebug: true)
            // Also send APNs so the extension receives the latest token-based update.
            if let token = pushToken {
                await APNSClient.shared.sendLiveActivityUpdate(pushToken: token, state: state)
            }
        }
    }

    @objc private func handleDidBecomeActive() {
        guard Storage.shared.laEnabled.value else { return }
        if skipNextDidBecomeActive {
            skipNextDidBecomeActive = false
            return
        }
        Task { @MainActor in
            self.startFromCurrentState()
        }
    }

    @objc private func handleForeground() {
        guard Storage.shared.laEnabled.value else { return }

        let renewalFailed = Storage.shared.laRenewalFailed.value
        let renewBy = Storage.shared.laRenewBy.value
        let now = Date().timeIntervalSince1970
        let overlayIsShowing = renewBy > 0 && now >= renewBy - LiveActivityManager.renewalWarning

        LogManager.shared.log(category: .general, message: "[LA] foreground notification received, laRenewalFailed=\(renewalFailed), overlayShowing=\(overlayIsShowing)")
        guard renewalFailed || overlayIsShowing else { return }

        // Overlay is showing or renewal previously failed — end the stale LA and start a fresh one.
        // We cannot call startIfNeeded() here: it finds the existing activity in
        // Activity.activities and reuses it rather than replacing it.
        LogManager.shared.log(category: .general, message: "[LA] ending stale LA and restarting (renewalFailed=\(renewalFailed), overlayShowing=\(overlayIsShowing))")
        // Suppress the handleDidBecomeActive() call that always fires after willEnterForeground.
        // Without this, the two methods race: didBecomeActive binds to the old (dying) activity
        // and observes its push token, while handleForeground's async end+restart creates a new
        // activity — leaving pushToken nil when the new activity tries to start.
        skipNextDidBecomeActive = true
        // Clear state synchronously so any snapshot built between now and when the
        // new LA is started computes showRenewalOverlay = false.
        Storage.shared.laRenewBy.value = 0
        Storage.shared.laRenewalFailed.value = false
        cancelRenewalFailedNotification()

        guard let activity = current else {
            startFromCurrentState()
            return
        }

        current = nil
        updateTask?.cancel()
        updateTask = nil
        tokenObservationTask?.cancel()
        tokenObservationTask = nil
        stateObserverTask?.cancel()
        stateObserverTask = nil
        pushToken = nil

        Task {
            // Await end so the activity is removed from Activity.activities before
            // startIfNeeded() runs — otherwise it hits the reuse path and skips
            // writing a new laRenewBy deadline.
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run {
                // Reset dismissedByUser in case the state observer fired .dismissed during
                // our own end() call (before its Task cancellation took effect) and
                // incorrectly set it to true — startFromCurrentState guards on this flag.
                self.dismissedByUser = false
                // startFromCurrentState rebuilds the snapshot (showRenewalOverlay = false
                // since laRenewBy is 0), saves it to the store, then calls startIfNeeded()
                // which finds no existing activity and requests a fresh LA with a new deadline.
                self.startFromCurrentState()
                LogManager.shared.log(category: .general, message: "[LA] Live Activity restarted after foreground retry")
            }
        }
    }

    @objc private func handleBackgroundAudioFailed() {
        guard Storage.shared.laEnabled.value, current != nil else { return }
        // The background audio session has permanently failed — the app will lose its
        // background keep-alive. Immediately push the renewal overlay so the user sees
        // "Tap to update" on the lock screen and knows to foreground the app.
        LogManager.shared.log(category: .general, message: "[LA] background audio failed — forcing renewal overlay")
        Storage.shared.laRenewBy.value = Date().timeIntervalSince1970
        refreshFromCurrentState(reason: "audio-session-failed")
    }

    static let renewalThreshold: TimeInterval = 7.5 * 3600
    static let renewalWarning: TimeInterval = 20 * 60

    private(set) var current: Activity<GlucoseLiveActivityAttributes>?
    private var stateObserverTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var seq: Int = 0
    private var lastUpdateTime: Date?
    private var pushToken: String?
    private var tokenObservationTask: Task<Void, Never>?
    private var refreshWorkItem: Task<Void, Never>?
    
    // MARK: - Public API

    func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            LogManager.shared.log(category: .general, message: "Live Activity not authorized")
            return
        }

        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            bind(to: existing, logReason: "reuse")
            return
        }

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
                unit: .mgdl,
                isNotLooping: false
            )

            let initialState = GlucoseLiveActivityAttributes.ContentState(
                snapshot: seedSnapshot,
                seq: 0,
                reason: "start",
                producedAt: Date()
            )

            let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(15 * 60))
            let activity = try Activity.request(attributes: attributes, content: content, pushType: .token)

            bind(to: activity, logReason: "start-new")
            LogManager.shared.log(category: .general, message: "Live Activity started id=\(activity.id)")
        } catch {
            LogManager.shared.log(category: .general, message: "Live Activity failed to start: \(error)")
        }
    }

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
                    unit: .mgdl,
                    isNotLooping: false
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

    func startFromCurrentState() {
        let provider = StorageCurrentGlucoseStateProvider()
        if let snapshot = GlucoseSnapshotBuilder.build(from: provider) {
            LAAppGroupSettings.setThresholds(
                lowMgdl: Storage.shared.lowLine.value,
                highMgdl: Storage.shared.highLine.value
            )
            GlucoseSnapshotStore.shared.save(snapshot)
        }
        startIfNeeded()
    }
    
    func refreshFromCurrentState(reason: String) {
        refreshWorkItem?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.performRefresh(reason: reason)
        }
        refreshWorkItem = task
    }
    
    private func performRefresh(reason: String) async {
        let provider = StorageCurrentGlucoseStateProvider()
        guard let snapshot = GlucoseSnapshotBuilder.build(from: provider) else {
            LogManager.shared.log(category: .general, message: "[LA] performRefresh: snapshot nil, skipping reason=\(reason)")
            return
        }

        let fingerprint =
            "g=\(snapshot.glucose) d=\(snapshot.delta) t=\(snapshot.trend.rawValue) " +
            "at=\(snapshot.updatedAt.timeIntervalSince1970) iob=\(snapshot.iob?.description ?? "nil") " +
            "cob=\(snapshot.cob?.description ?? "nil") proj=\(snapshot.projected?.description ?? "nil") u=\(snapshot.unit.rawValue)"
        LogManager.shared.log(category: .general, message: "[LA] snapshot \(fingerprint) reason=\(reason)", isDebug: true)

        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime ?? .distantPast)
        let forceRefreshNeeded = timeSinceLastUpdate >= 5 * 60
        if let previous = GlucoseSnapshotStore.shared.load(), previous == snapshot, !forceRefreshNeeded {
            return
        }

        LAAppGroupSettings.setThresholds(
            lowMgdl: Storage.shared.lowLine.value,
            highMgdl: Storage.shared.highLine.value
        )
        GlucoseSnapshotStore.shared.save(snapshot)
        WatchConnectivityManager.shared.send(snapshot: snapshot)

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Resolve activity state — three cases handled serially with no timing dependency.
        if current == nil {
            if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
                if existing.activityState == .ended || existing.activityState == .dismissed {
                    // Dying activity still in system list. End it and wait before starting fresh.
                    LogManager.shared.log(category: .general, message: "[LA] stale activity found, ending before restart id=\(existing.id)")
                    await existing.end(nil, dismissalPolicy: .immediate)
                    LogManager.shared.log(category: .general, message: "[LA] stale activity ended, starting fresh")
                    startIfNeeded()
                } else {
                    // Healthy activity we don't have a reference to — bind it.
                    bind(to: existing, logReason: "bind-existing")
                }
            } else {
                // No activity in system at all — start one if visible.
                if isAppVisibleForLiveActivityStart() {
                    startIfNeeded()
                } else {
                    LogManager.shared.log(category: .general, message: "[LA] start suppressed (not visible) reason=\(reason)", isDebug: true)
                }
            }
        }

        if let _ = current {
            update(snapshot: snapshot, reason: reason)
        }
    }
    
    private func isAppVisibleForLiveActivityStart() -> Bool {
        let scenes = UIApplication.shared.connectedScenes
        return scenes.contains { $0.activationState == .foregroundActive }
    }

    func update(snapshot: GlucoseSnapshot, reason: String) {
        if current == nil, let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            bind(to: existing, logReason: "bind-existing")
        }

        guard let activity = current else { return }

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

            if activity.activityState == .ended || activity.activityState == .dismissed {
                LogManager.shared.log(category: .general, message: "[LA] update dropped — activity ended/dismissed id=\(activityID) seq=\(nextSeq)")
                if self.current?.id == activityID { self.current = nil }
                return
            }

            let content = ActivityContent(
                state: state,
                staleDate: Date().addingTimeInterval(15 * 60),
                relevanceScore: 100.0
            )

            if Task.isCancelled { return }

            // Dual-path update strategy:
            // - Foreground: direct ActivityKit update works reliably.
            // - Background: direct update silently fails due to the audio session
            //   limitation. APNs self-push is the only reliable delivery path.
            //   Both paths are attempted when applicable; APNs is the authoritative
            //   background mechanism.
            let isForeground = await MainActor.run {
                UIApplication.shared.applicationState == .active
            }

            if isForeground {
                await activity.update(content)
            }

            if Task.isCancelled { return }

            guard self.current?.id == activityID else {
                LogManager.shared.log(category: .general, message: "Live Activity update — activity ID mismatch, discarding")
                return
            }

            self.lastUpdateTime = Date()
            LogManager.shared.log(category: .general, message: "[LA] updated id=\(activityID) seq=\(nextSeq) reason=\(reason)", isDebug: true)

            if let token = self.pushToken {
                await APNSClient.shared.sendLiveActivityUpdate(pushToken: token, state: state)
            }
        }
    }

    // MARK: - Binding / Lifecycle

    private func bind(to activity: Activity<GlucoseLiveActivityAttributes>, logReason: String) {
        if current?.id == activity.id { return }
        current = activity
        attachStateObserver(to: activity)
        LogManager.shared.log(category: .general, message: "Live Activity bound id=\(activity.id) (\(logReason))", isDebug: true)
        observePushToken(for: activity)
    }

    private func observePushToken(for activity: Activity<GlucoseLiveActivityAttributes>) {
        tokenObservationTask?.cancel()
        tokenObservationTask = Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                self.pushToken = token
                LogManager.shared.log(category: .general, message: "Live Activity push token received", isDebug: true)
            }
        }
    }

    func handleExpiredToken() {
        end()
        // Activity will restart on next BG refresh via refreshFromCurrentState()
    }
    
    private func attachStateObserver(to activity: Activity<GlucoseLiveActivityAttributes>) {
        stateObserverTask?.cancel()
        stateObserverTask = Task {
            for await state in activity.activityStateUpdates {
                LogManager.shared.log(category: .general, message: "Live Activity state id=\(activity.id) -> \(state)", isDebug: true)
                if state == .ended || state == .dismissed {
                    if current?.id == activity.id {
                        current = nil
                        LogManager.shared.log(category: .general, message: "Live Activity cleared id=\(activity.id)", isDebug: true)
                    }
                    if state == .dismissed {
                        // Distinguish system-initiated dismissal from a user swipe.
                        // iOS dismisses the activity when (a) the renewal limit was reached
                        // with a failed renewal, or (b) the staleDate passed and iOS decided
                        // to remove the activity. In both cases auto-restart is appropriate.
                        // Only a true user swipe (activity still fresh) should block restart.
                        let staleDatePassed = activity.content.staleDate.map { $0 <= Date() } ?? false
                        if Storage.shared.laRenewalFailed.value || staleDatePassed {
                            LogManager.shared.log(category: .general, message: "Live Activity dismissed by iOS (renewalFailed=\(Storage.shared.laRenewalFailed.value), staleDatePassed=\(staleDatePassed)) — auto-restart enabled")
                        } else {
                            // User manually swiped away the LA. Block auto-restart until
                            // the user explicitly restarts via button or App Intent.
                            // laEnabled is left true — the user's preference is preserved.
                            dismissedByUser = true
                            LogManager.shared.log(category: .general, message: "Live Activity dismissed by user — auto-restart blocked until explicit restart")
                        }
                    }
                }
            }
        }
    }
}
