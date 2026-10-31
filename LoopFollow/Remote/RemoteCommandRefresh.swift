// LoopFollow
// RemoteCommandRefresh.swift

import Foundation
import HealthKit

/// Loop and Trio apply a remote command within seconds, but LoopFollow only sees
/// the result on its next regular Nightscout fetch, which can be minutes away.
/// After a command is sent, treatments and device status are fetched a few extra
/// times, stopping as soon as the change the command makes shows up, so the new
/// override, temp target, bolus or carbs reach the phone, the watch and the Live
/// Activity sooner.
final class RemoteCommandRefresh {
    /// What a command changes, and so what ends the follow-up fetches.
    enum Change {
        case override
        case tempTarget
        case bolus(units: Double)
        case carbs(grams: Double)

        var name: String {
            switch self {
            case .override: "override"
            case .tempTarget: "temp target"
            case .bolus: "bolus"
            case .carbs: "carbs"
            }
        }
    }

    static let shared = RemoteCommandRefresh()

    /// Seconds after the send. Most uploads land in the first half minute; the
    /// later fetches cover a pump that is slow to deliver or an upload that is retried.
    static let delays: [TimeInterval] = [10, 20, 30, 60, 90, 120]

    private var pending: [DispatchWorkItem] = []

    private init() {}

    /// Wraps a send's completion so that a successful send starts the follow-up fetches.
    static func following(_ change: Change, _ completion: @escaping (Bool, String?) -> Void) -> (Bool, String?) -> Void {
        { success, error in
            if success { shared.commandSent(change) }
            completion(success, error)
        }
    }

    /// Restarts the follow-up fetches; a newer command replaces the remaining ones.
    func commandSent(_ change: Change) {
        DispatchQueue.main.async {
            self.cancel()
            let arrived = Self.arrivalCheck(for: change)
            LogManager.shared.log(category: .apns, message: "Fetching Nightscout early until the \(change.name) shows up")
            self.pending = Self.delays.enumerated().map { index, delay in
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if arrived() {
                        LogManager.shared.log(category: .apns, message: "The \(change.name) showed up; \(Self.delays.count - index) early fetches skipped")
                        self.cancel()
                        return
                    }
                    TaskScheduler.shared.rescheduleTask(id: .treatments, to: Date())
                    TaskScheduler.shared.rescheduleTask(id: .deviceStatus, to: Date())
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                return work
            }
        }
    }

    private func cancel() {
        pending.forEach { $0.cancel() }
        pending = []
    }

    /// Captures the phone's data now and returns a check that is true once the
    /// command's change is in it. A change that never matches (a partial bolus,
    /// a renamed preset) only means the fetches run their full two minutes.
    private static func arrivalCheck(for change: Change) -> () -> Bool {
        switch change {
        case .override:
            let before = (Observable.shared.override.value, Observable.shared.overrideEndAt.value)
            return { (Observable.shared.override.value, Observable.shared.overrideEndAt.value) != before }
        case .tempTarget:
            let before = (Observable.shared.tempTarget.value, Observable.shared.tempTargetEndAt.value)
            return { (Observable.shared.tempTarget.value, Observable.shared.tempTargetEndAt.value) != before }
        case let .bolus(units):
            let known = Set(boluses().map { $0.date })
            return { boluses().contains { !known.contains($0.date) && abs($0.value - units) < 0.01 } }
        case let .carbs(grams):
            let known = Set(carbs().map { $0.date })
            return { carbs().contains { !known.contains($0.date) && abs($0.value - grams) < 0.5 } }
        }
    }

    private static func boluses() -> [(date: TimeInterval, value: Double)] {
        let vc = MainViewController.shared
        return ((vc?.bolusData ?? []) + (vc?.smbData ?? [])).map { (date: $0.date, value: $0.value) }
    }

    private static func carbs() -> [(date: TimeInterval, value: Double)] {
        (MainViewController.shared?.carbData ?? []).map { (date: $0.date, value: $0.value) }
    }
}
