//
//  LAHealthStore.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-21.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation

enum LAHealthStore {
    private static let suiteName = "group.com.2HEY366Q6J.LoopFollow"
    private static let suite = UserDefaults(suiteName: suiteName)

    private enum K {
        static let lastUpdateStartEpoch = "la_last_update_start_epoch"
        static let lastUpdateSuccessEpoch = "la_last_update_success_epoch"
        static let lastHealTag = "la_last_heal_tag"
    }

    static func setLastUpdateStart(_ epoch: Int) {
        suite?.set(epoch, forKey: K.lastUpdateStartEpoch)
    }

    static func setLastUpdateSuccess(_ epoch: Int) {
        suite?.set(epoch, forKey: K.lastUpdateSuccessEpoch)
    }

    static func lastUpdateStart() -> Int? {
        let v = suite?.object(forKey: K.lastUpdateStartEpoch) as? Int
        return v
    }

    static func lastUpdateSuccess() -> Int? {
        let v = suite?.object(forKey: K.lastUpdateSuccessEpoch) as? Int
        return v
    }

    static func setLastHealTag(_ tag: String) {
        suite?.set(tag, forKey: K.lastHealTag)
    }

    static func lastHealTag() -> String? {
        suite?.string(forKey: K.lastHealTag)
    }
    
    private static var suiteName: String {
        // Cleaner option B: dynamic group id
        "group.\(Bundle.main.bundleIdentifier ?? "LoopFollow")"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Keys

    private static let kCurrentActivityId = "la.currentActivityId"

    // MARK: - Current Activity ID

    static func setCurrentActivityId(_ id: String) {
        defaults.set(id, forKey: kCurrentActivityId)
    }

    static func currentActivityId() -> String? {
        let id = defaults.string(forKey: kCurrentActivityId)
        return (id?.isEmpty == false) ? id : nil
    }

    static func clearCurrentActivityId() {
        defaults.removeObject(forKey: kCurrentActivityId)
    }

}
