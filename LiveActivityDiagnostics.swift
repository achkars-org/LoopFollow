// LiveActivityDiagnostics.swift
// Philippe Achkar
// 2026-02-28

import Foundation
import ActivityKit

@available(iOS 16.1, *)
enum LiveActivityDiagnostics {

    static func dump(source: String) {
        let activities = Activity<GlucoseLiveActivityAttributes>.activities

        LogManager.shared.log(category: .debug, message: "[LA DIAG] dump source=\(source) count=\(activities.count)")

        if let a = activities.first {
            LogManager.shared.log(category: .debug, message: "[LA DIAG] first id=\(a.id) state=\(a.activityState)")
        }

        // Snapshot builder inputs
        LogManager.shared.log(category: .debug, message: "[LA DIAG] Observable.bg=\(Observable.shared.bg.value)")

        LogManager.shared.log(
            category: .debug,
            message: "[LA DIAG] Storage t=\(Storage.shared.lastBgReadingTimeSeconds.value?.description ?? "nil") " +
                     "Δmgdl=\(Storage.shared.lastDeltaMgdl.value?.description ?? "nil") " +
                     "trend=\(Storage.shared.lastTrendCode.value ?? "nil") " +
                     "iob=\(Storage.shared.lastIOB.value?.description ?? "nil") " +
                     "cob=\(Storage.shared.lastCOB.value?.description ?? "nil") " +
                     "proj=\(Storage.shared.projectedBgMgdl.value?.description ?? "nil") " +
                     "units=\(Storage.shared.units.value)"
        )

        let provider = StorageCurrentGlucoseStateProvider()
        let snap = GlucoseSnapshotBuilder.build(from: provider)
        LogManager.shared.log(category: .debug, message: "[LA DIAG] builder snapshot is \(snap == nil ? "nil" : "NON-nil")")
    }
}
