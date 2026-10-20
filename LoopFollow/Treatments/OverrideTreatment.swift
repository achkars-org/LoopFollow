// LoopFollow
// OverrideTreatment.swift

import Foundation

/// Parameters of a Nightscout "Temporary Override" treatment, from Loop or Trio.
struct OverrideTreatment: Equatable {
    /// Loop marks indefinite overrides explicitly; Trio represents them as a
    /// ~30-day duration, so a week or longer counts as indefinite.
    static let indefiniteThreshold: TimeInterval = 7 * 24 * 3600

    let name: String
    let start: TimeInterval
    /// Planned end, or the actual end once the override was cut short; nil while indefinite.
    private(set) var end: TimeInterval?
    /// Insulin needs multiplier, e.g. 1.25 for 125 %.
    let insulinNeedsScaleFactor: Double?
    /// Correction range in mg/dL; nil when the override keeps the scheduled range.
    let targetRange: ClosedRange<Double>?
    let enteredBy: String?

    init?(nightscoutEntry entry: [String: AnyObject], date: TimeInterval) {
        guard let eventType = entry["eventType"] as? String,
              eventType == "Temporary Override" || eventType == "Exercise"
        else { return nil }

        // Loop updates the duration to the actual length when an override ends early.
        let minutes = (entry["duration"] as? NSNumber)?.doubleValue ?? 0
        let indefinite = (entry["durationType"] as? String) == "indefinite" || minutes * 60 >= Self.indefiniteThreshold
        guard indefinite || minutes > 0 else { return nil }

        // Loop stores the override name in "reason"; Trio stores it in "notes".
        let note = (entry["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (entry["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        name = [note, reason].compactMap { $0 }.first { !$0.isEmpty } ?? "Temporary Override"

        start = date
        end = indefinite ? nil : date + minutes * 60
        insulinNeedsScaleFactor = (entry["insulinNeedsScaleFactor"] as? NSNumber)?.doubleValue

        let range = (entry["correctionRange"] as? [NSNumber])?.map(\.doubleValue)
        let bottom = (entry["targetBottom"] as? NSNumber)?.doubleValue ?? 0
        let top = (entry["targetTop"] as? NSNumber)?.doubleValue ?? 0
        if let range, range.count == 2, range[0] > 0, range[0] <= range[1] {
            targetRange = range[0] ... range[1]
        } else if bottom > 0, top >= bottom {
            targetRange = bottom ... top
        } else {
            targetRange = nil
        }

        let author = (entry["enteredBy"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        enteredBy = author?.isEmpty == false ? author : nil
    }

    var isIndefinite: Bool { end == nil }

    var duration: TimeInterval? { end.map { $0 - start } }

    func isActive(at now: TimeInterval) -> Bool {
        start <= now && end.map { now < $0 } != false
    }

    /// The same override ended at `time` when that is before its own end, e.g.
    /// because the next override replaced it.
    func ending(at time: TimeInterval) -> OverrideTreatment {
        guard time > start, end.map({ time < $0 }) ?? true else { return self }
        var copy = self
        copy.end = time
        return copy
    }
}
