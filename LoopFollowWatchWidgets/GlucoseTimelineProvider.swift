// LoopFollow
// GlucoseTimelineProvider.swift

import WidgetKit

struct GlucoseEntry: TimelineEntry {
    let date: Date
    let snapshot: GlucoseSnapshot?
    let history: [WatchGlucoseHistory.Point]

    /// Readings older than this are dimmed and lose their trend and delta, but keep their value.
    static let staleAfter: TimeInterval = 15 * 60
    /// A projection is shown (with the reading's age beside it) until the reading is this old.
    static let projectionExpiredAfter: TimeInterval = 30 * 60
    /// Readings older than this are too old to show and render as "--".
    static let expiredAfter: TimeInterval = 60 * 60

    /// Age of the reading at the time this entry is displayed.
    var readingAge: TimeInterval? {
        snapshot.map { date.timeIntervalSince($0.updatedAt) }
    }

    var isStale: Bool {
        guard let readingAge else { return true }
        return readingAge >= Self.staleAfter || snapshot?.isNotLooping == true
    }

    var isProjectionExpired: Bool {
        guard let readingAge else { return true }
        return readingAge >= Self.projectionExpiredAfter || snapshot?.isNotLooping == true
    }

    var isExpired: Bool {
        guard let readingAge else { return true }
        return readingAge >= Self.expiredAfter || snapshot?.isNotLooping == true
    }

    /// Age of the reading as "22m", capped at two digits.
    var ageText: String {
        guard let readingAge else { return "" }
        return "\(min(Int(readingAge / 60), 99))m"
    }

    /// Joins the non-empty parts with single spaces, for compact complication labels.
    func label(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The delta while the reading is fresh, its age once it has gone stale.
    func deltaOrAge(delta: String) -> String {
        isStale && !isExpired ? ageText : delta
    }

    static let placeholder = GlucoseEntry(
        date: Date(),
        snapshot: GlucoseSnapshot(
            glucose: 112,
            delta: 2,
            trend: .flat,
            updatedAt: Date(),
            iob: nil,
            cob: nil,
            projected: nil,
            unit: .mgdl,
            isNotLooping: false
        ),
        history: []
    )
}

/// Reads the snapshot and history the Watch app persisted in the App Group. The Watch
/// app reloads this timeline whenever new data arrives; the provider only fetches from
/// Nightscout itself when the stored reading has gone stale.
struct GlucoseTimelineProvider: TimelineProvider {
    /// One entry per minute lets the age label and stale state advance without reloads.
    private static let entryCount = 60

    func placeholder(in _: Context) -> GlucoseEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (GlucoseEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<GlucoseEntry>) -> Void) {
        let now = Date()
        let stored = GlucoseSnapshotStore.shared.load()
        guard Self.needsFetch(stored, now: now) else {
            completion(timeline(snapshot: stored, now: now))
            return
        }
        // The phone's push or the Watch's own wake did not bring a fresh reading, so ask
        // Nightscout directly rather than let the face age.
        WatchNightscoutClient.fetchLatest { result in
            guard case let .success(fetched) = result, fetched.updatedAt > (stored?.updatedAt ?? .distantPast) else {
                if case .failure = result {
                    WatchEventLog.record("widget", "Nightscout fetch failed", coalescing: true)
                }
                completion(timeline(snapshot: stored, now: Date()))
                return
            }
            WatchEventLog.record("widget", "fetched from Nightscout, reading \(Int(Date().timeIntervalSince(fetched.updatedAt) / 60))m old")
            GlucoseSnapshotStore.shared.save(fetched) {
                completion(timeline(snapshot: fetched, now: Date()))
            }
        }
    }

    /// A reading arrives every five minutes, so one over ten minutes old was missed.
    private static let fetchAfter: TimeInterval = 10 * 60
    /// How soon WidgetKit is asked to call again; it applies its own budget on top.
    private static let refreshInterval: TimeInterval = 15 * 60

    private static func needsFetch(_ snapshot: GlucoseSnapshot?, now: Date) -> Bool {
        guard let snapshot else { return true }
        return now.timeIntervalSince(snapshot.updatedAt) >= fetchAfter
    }

    private func timeline(snapshot: GlucoseSnapshot?, now: Date) -> Timeline<GlucoseEntry> {
        let history = WatchGlucoseHistory.load()?.points ?? []
        let ageText = snapshot.map { "\(Int(now.timeIntervalSince($0.updatedAt) / 60))m old" } ?? "none"
        WatchEventLog.record("widget", "timeline built, reading \(ageText)")
        let entries = (0 ..< Self.entryCount).map { minute in
            GlucoseEntry(date: now.addingTimeInterval(TimeInterval(minute) * 60), snapshot: snapshot, history: history)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.refreshInterval)))
    }

    private func entry(at date: Date) -> GlucoseEntry {
        GlucoseEntry(
            date: date,
            snapshot: GlucoseSnapshotStore.shared.load(),
            history: WatchGlucoseHistory.load()?.points ?? []
        )
    }
}
