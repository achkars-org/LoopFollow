//
//  StorageCurrentGlucoseStateProvider.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-24.
//

import Foundation

/// Reads the latest glucose state from LoopFollow’s existing single source of truth (Storage/Observable).
/// Provider remains source-agnostic (Nightscout vs Dexcom).
struct StorageCurrentGlucoseStateProvider: CurrentGlucoseStateProviding {

    var glucoseMgdl: Double? {
        // Observable.shared.bg.value is raw mg/dL (set in viewUpdateNSBG today).
        // If you later migrate to a Storage raw BG value, change only here.
        let bg = Observable.shared.bg.value
        return bg > 0 ? Double(bg) : nil
    }

    var deltaMgdl: Double? {
        Storage.shared.lastDeltaMgdl.value
    }

    var projectedMgdl: Double? {
        let v = Storage.shared.projectedBgMgdl.value
        return v >= 0 ? v : nil
    }

    var updatedAt: Date? {
        let t = Storage.shared.lastBgReadingTimeSeconds.value
        guard t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    var trendCode: String? {
        let s = Storage.shared.lastTrendCode.value
        return s.isEmpty ? nil : s
    }

    var iob: Double? {
        let v = Storage.shared.lastIOB.value
        return v >= 0 ? v : nil
    }

    var cob: Double? {
        let v = Storage.shared.lastCOB.value
        return v >= 0 ? v : nil
    }
}