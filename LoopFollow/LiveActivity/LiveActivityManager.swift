import Foundation
import ActivityKit

final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private(set) var current: Activity<GlucoseLiveActivityAttributes>?

    // Observe lifecycle changes (ended/dismissed)
    private var stateObserverTask: Task<Void, Never>?

    // Serialize updates
    private var updateTask: Task<Void, Never>?

    // Watchdog
    private var watchdogTask: Task<Void, Never>?

    // MARK: - Health / Debug Tracking

    private var seq: Int = 0
    private var lastUpdateStartAt: Date?
    private var lastUpdateSuccessAt: Date?
    private var consecutiveFailures: Int = 0

    // Tag to carry heal reason into the next Activity start (visible in the UI)
    private var pendingStartDebugTag: String?

    private let staleMaxAgeSeconds: TimeInterval = 15 * 60
    private let hungUpdateMaxSeconds: TimeInterval = 90
    private let watchdogIntervalSeconds: TimeInterval = 60

    // MARK: - Stage vocabulary

    private enum LAStage: String {
        case start      = "START"
        case trig       = "TRIG"
        case bind       = "BIND"
        case snap       = "SNAP"
        case merge      = "MERGE"
        case updAttempt = "UPD_ATTEMPT"
        case updOk      = "UPD_OK"
        case zombie     = "ZOMBIE"
        case stale      = "STALE"
        case hung       = "HUNG"
        case healStale  = "HEAL_STALE"
        case healHung   = "HEAL_HUNG"
        case end        = "END"
        case state      = "STATE"
    }

    // MARK: - Start / Reuse

    func startIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log(.zombie, source: "startIfNeeded", msg: "not authorized")
            return
        }

        // Reuse only an ACTIVE activity (never reuse ended/dismissed)
        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
        
            if current?.id != existing.id {
                current = existing
                attachStateObserver(to: existing)
                log(.bind, source: "startIfNeeded", msg: "reuse ACTIVE id=\(existing.id)")
            }
        
            startWatchdogIfNeeded()
            return
        }
        
        // If we have activities but none are active, log it (super useful)
        let all = Activity<GlucoseLiveActivityAttributes>.activities
        if !all.isEmpty {
            let states = all.map { "\($0.id.suffix(6)):\($0.activityState)" }.joined(separator: ",")
            log(.zombie, source: "startIfNeeded", msg: "no ACTIVE to reuse; existing=\(states)")
        }

        let attributes = GlucoseLiveActivityAttributes(title: "LoopFollow")

        let now = Date()
        let epoch = Int(now.timeIntervalSince1970)

        // Pull persisted heal tag if present (survives app restarts)
        let storedHeal = LAHealthStore.lastHealTag()
        let startTag = pendingStartDebugTag ?? storedHeal ?? LAStage.start.rawValue

        // Clear after consuming so it doesn't repeat forever
        pendingStartDebugTag = nil
        LAHealthStore.setLastHealTag("")

        let initial = GlucoseLiveActivityAttributes.ContentState(
            glucoseMmol: nil,
            previousGlucoseMmol: nil,
            trend: nil,
            iob: nil,
            cob: nil,
            projectedMmol: nil,
            updatedAt: now,
            seq: 0,
            debug: startTag,
            updatedAtEpoch: epoch
        )

        do {
            let content = ActivityContent(
                state: initial,
                staleDate: now.addingTimeInterval(15 * 60)
            )

            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )

            current = activity
            attachStateObserver(to: activity)
            startWatchdogIfNeeded()

            log(.start, source: "startIfNeeded", msg: "started id=\(activity.id) tag=\(startTag)")
        } catch {
            log(.zombie, source: "startIfNeeded", msg: "start error: \(error)")
        }
    }

    // MARK: - Refresh entry points

    /// The *only* refresh you should call from elsewhere.
    /// Use a clear source string: "silent_push", "poll", "manual", etc.
    func refreshFromCurrentState(source: String) async {
        startIfNeeded()
        startWatchdogIfNeeded()

        // Cancel any in-flight update; newest wins
        updateTask?.cancel()

        updateTask = Task { [weak self] in
            guard let self else { return }

            // Single time base for start markers
            let nowStart = Date()
            self.lastUpdateStartAt = nowStart
            LAHealthStore.setLastUpdateStart(Int(nowStart.timeIntervalSince1970))

            self.log(.trig, source: source, msg: "refresh requested")

            // If this task got cancelled immediately, stop.
            if Task.isCancelled {
                self.consecutiveFailures += 1
                self.log(.zombie, source: source, msg: "cancelled before bind")
                return
            }

            // Stage: bind/rebind
            guard let activity = self.boundActivityOrRebind() else {
                self.consecutiveFailures += 1
                self.log(.zombie, source: source, msg: "no active Activity to update")
                return
            }

            let all = Activity<GlucoseLiveActivityAttributes>.activities
            let suffixes = all.map { String($0.id.suffix(6)) }.joined(separator: ",")
            let boundSuffix = String(activity.id.suffix(6))
            
            self.log(
                .bind,
                source: source,
                msg: "bound=\(boundSuffix) all=[\(suffixes)] count=\(all.count)"
            )

            if Task.isCancelled {
                self.consecutiveFailures += 1
                self.log(.zombie, source: source, msg: "cancelled after bind")
                return
            }

            // Stage: snapshot
            let glucose = Storage.shared.currentGlucoseMmol.value
            let previous = Storage.shared.previousGlucoseMmol.value
            let trend = Storage.shared.trendArrow.value
            let iobFresh = Storage.shared.latestIOB.value
            let cobFresh = Storage.shared.latestCOB.value
            let projected = Storage.shared.projectedMmol.value

            self.log(
                .snap,
                source: source,
                msg: "g=\(self.f1(glucose)) prev=\(self.f1(previous)) t=\(trend ?? "nil") i=\(self.f2(iobFresh)) c=\(self.f0(cobFresh)) p=\(self.f1(projected))"
            )

            // Stage: merge cache
            let cachedIOB = LAStateCache.loadIOB()
            let cachedCOB = LAStateCache.loadCOB()
            let mergedIOB = iobFresh ?? cachedIOB
            let mergedCOB = cobFresh ?? cachedCOB
            LAStateCache.save(iob: mergedIOB, cob: mergedCOB)

            self.log(
                .merge,
                source: source,
                msg: "merged i=\(self.f2(mergedIOB)) c=\(self.f0(mergedCOB)) (freshMissing i=\(iobFresh == nil) c=\(cobFresh == nil))"
            )

            if Task.isCancelled {
                self.consecutiveFailures += 1
                self.log(.zombie, source: source, msg: "cancelled before update")
                return
            }

            // Stage: update attempt — stamp debug into ContentState
            self.seq += 1
            let now = Date()
            let epoch = Int(now.timeIntervalSince1970)

            let idSuffix = String(activity.id.suffix(6))
            let debug = "\(LAStage.updAttempt.rawValue) src=\(source) #\(self.seq) id=\(idSuffix)"
            
            let state = GlucoseLiveActivityAttributes.ContentState(
                glucoseMmol: glucose,
                previousGlucoseMmol: previous,
                trend: trend,
                iob: mergedIOB,
                cob: mergedCOB,
                projectedMmol: projected,
                updatedAt: now,
                seq: self.seq,
                debug: debug,
                updatedAtEpoch: epoch
            )

            let content = ActivityContent(
                state: state,
                staleDate: now.addingTimeInterval(15 * 60)
            )

            self.log(.updAttempt, source: source, msg: "id=\(activity.id) seq=\(self.seq)")

            // ActivityKit update (non-throwing)
            await activity.update(content)

            if Task.isCancelled {
                // Update landed, but task cancelled immediately after; still record it
                self.log(.state, source: source, msg: "cancelled after update")
            }

            // Mark success using a single time base
            let nowSuccess = Date()
            self.lastUpdateSuccessAt = nowSuccess
            LAHealthStore.setLastUpdateSuccess(Int(nowSuccess.timeIntervalSince1970))

            self.consecutiveFailures = 0
            self.log(.updOk, source: source, msg: "id=\(activity.id) seq=\(self.seq)")
        }
    }
    /// Backward-compatible convenience for existing callers.
    /// Prefer calling `refreshFromCurrentState(source:)` explicitly.
    func refreshFromCurrentState() async {
        await refreshFromCurrentState(source: "unknown")
    }

    // MARK: - End

    func end() {
        guard let activity = Activity<GlucoseLiveActivityAttributes>.activities.first else { return }

        let now = Date()
        let epoch = Int(now.timeIntervalSince1970)

        let finalSeq = seq + 1

        let finalState = GlucoseLiveActivityAttributes.ContentState(
            glucoseMmol: Storage.shared.currentGlucoseMmol.value,
            previousGlucoseMmol: Storage.shared.previousGlucoseMmol.value,
            trend: Storage.shared.trendArrow.value,
            iob: Storage.shared.latestIOB.value,
            cob: Storage.shared.latestCOB.value,
            projectedMmol: Storage.shared.projectedMmol.value,
            updatedAt: now,
            seq: finalSeq,
            debug: LAStage.end.rawValue,
            updatedAtEpoch: epoch
        )

        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        let id = activity.id

        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
            log(.end, source: "end()", msg: "ended id=\(id) seq=\(finalSeq)")
        }
    }

    // MARK: - Watchdog / Auto-Heal

    private func startWatchdogIfNeeded() {
        if watchdogTask != nil { return }

        watchdogTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.repairIfStale()
                await self.repairIfHung()
                try? await Task.sleep(nanoseconds: UInt64(self.watchdogIntervalSeconds * 1_000_000_000))
            }
        }

        log(.state, source: "watchdog", msg: "started interval=\(Int(watchdogIntervalSeconds))s")
    }

    private func repairIfStale() async {
        let lastOK: Date? = {
            if let d = lastUpdateSuccessAt { return d }
            if let epoch = LAHealthStore.lastUpdateSuccess() {
                return Date(timeIntervalSince1970: TimeInterval(epoch))
            }
            return nil
        }()

        guard let lastOK else { return }

        let age = Date().timeIntervalSince(lastOK)

        if age > staleMaxAgeSeconds {
            log(.stale, source: "watchdog", msg: "no success for \(Int(age))s")
            await heal(reasonStage: .healStale, details: "age=\(Int(age))s")
        }
    }

    private func repairIfHung() async {
        let start: Date? = {
            if let d = lastUpdateStartAt { return d }
            if let epoch = LAHealthStore.lastUpdateStart() {
                return Date(timeIntervalSince1970: TimeInterval(epoch))
            }
            return nil
        }()

        guard let start else { return }

        let lastOK: Date? = {
            if let d = lastUpdateSuccessAt { return d }
            if let epoch = LAHealthStore.lastUpdateSuccess() {
                return Date(timeIntervalSince1970: TimeInterval(epoch))
            }
            return nil
        }()

        if let lastOK, lastOK >= start { return }

        let hung = Date().timeIntervalSince(start)

        if hung > hungUpdateMaxSeconds {
            log(.hung, source: "watchdog", msg: "update started \(Int(hung))s ago, no success")
            updateTask?.cancel()
            await heal(reasonStage: .healHung, details: "hung=\(Int(hung))s")
        }
    }

    private func heal(reasonStage: LAStage, details: String) async {
        // Build heal tag (visible on next START)
        let healTag = "\(reasonStage.rawValue) \(details)"
        pendingStartDebugTag = healTag

        // Persist so it survives process death
        LAHealthStore.setLastHealTag(healTag)

        if let activity = boundActivityOrRebind() {
            log(reasonStage, source: "watchdog", msg: "ending id=\(activity.id) \(details)")
            let finalState = GlucoseLiveActivityAttributes.ContentState(
                glucoseMmol: Storage.shared.currentGlucoseMmol.value,
                previousGlucoseMmol: Storage.shared.previousGlucoseMmol.value,
                trend: Storage.shared.trendArrow.value,
                iob: Storage.shared.latestIOB.value,
                cob: Storage.shared.latestCOB.value,
                projectedMmol: Storage.shared.projectedMmol.value,
                updatedAt: Date(),
                seq: self.seq,
                debug: "END",
                updatedAtEpoch: Int(Date().timeIntervalSince1970)
            )
            let finalContent = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
        } else {
            log(reasonStage, source: "watchdog", msg: "no Activity to end \(details)")
        }

        current = nil
        stateObserverTask?.cancel()
        stateObserverTask = nil
        updateTask?.cancel()
        updateTask = nil

        // Restart
        startIfNeeded()

        log(reasonStage, source: "watchdog", msg: "restarted \(details)")
    }

    // MARK: - Helpers

    private func boundActivityOrRebind() -> Activity<GlucoseLiveActivityAttributes>? {
        if let cur = current,
           Activity<GlucoseLiveActivityAttributes>.activities.contains(where: { $0.id == cur.id }) {
            return cur
        }

        if let existing = Activity<GlucoseLiveActivityAttributes>.activities.first {
            current = existing
            attachStateObserver(to: existing)
            return existing
        }

        current = nil
        return nil
    }

    private func attachStateObserver(to activity: Activity<GlucoseLiveActivityAttributes>) {
        stateObserverTask?.cancel()
        stateObserverTask = Task {
            for await state in activity.activityStateUpdates {
                LogManager.shared.log(category: .liveactivities, message: "[LA] \(LAStage.state.rawValue) id=\(activity.id) -> \(state)")
                if state == .ended || state == .dismissed {
                    if current?.id == activity.id {
                        current = nil
                        LogManager.shared.log(category: .liveactivities, message: "[LA] \(LAStage.state.rawValue) cleared current id=\(activity.id)")
                    }
                }
            }
        }
    }

    // Unified logger (grep-friendly)
    private func log(_ stage: LAStage, source: String, msg: String) {
        let t = Int(Date().timeIntervalSince1970)
        let id = current?.id ?? Activity<GlucoseLiveActivityAttributes>.activities.first?.id ?? "nil"
        LogManager.shared.log(
            category: .liveactivities,
            message: "[LA] \(stage.rawValue) t=\(t) src=\(source) id=\(id) seq=\(seq) \(msg)"
        )
    }

    // Small formatting helpers (avoid noisy logs)
    private func f1(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "nil" }
    private func f2(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }
    private func f0(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "nil" }
}
