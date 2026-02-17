//
//  LAStateCache.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-17.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation

enum LAStateCache {

    // ⚠️ Same App Group used for P1 Fix
    static let suite = UserDefaults(suiteName: "group.com.your.bundle")!

    private static let iobKey = "la_last_iob"
    private static let cobKey = "la_last_cob"

    static func save(iob: Double?, cob: Double?) {
        if let iob {
            suite.set(iob, forKey: iobKey)
        }
        if let cob {
            suite.set(cob, forKey: cobKey)
        }
    }

    static func loadIOB() -> Double? {
        if suite.object(forKey: iobKey) == nil { return nil }
        return suite.double(forKey: iobKey)
    }

    static func loadCOB() -> Double? {
        if suite.object(forKey: cobKey) == nil { return nil }
        return suite.double(forKey: cobKey)
    }
}
