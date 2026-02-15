//
//  NightscoutConfigStore.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-15.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation

enum NightscoutConfigStore {
    // ✅ Put your exact App Group ID here (the one you just enabled)
    private static let appGroupID = "group.com.2HEY366Q6J.LoopFollow"

    private static let baseURLKey = "nightscout.baseURL"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func getBaseURL() -> String? {
        defaults?.string(forKey: baseURLKey)
    }

    @discardableResult
    static func setBaseURL(_ url: String) -> Bool {
        // Normalize: trim + remove trailing slash
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)

        // Validate
        guard let u = URL(string: trimmed),
              let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }

        defaults?.set(trimmed, forKey: baseURLKey)
        // Ensure it’s flushed quickly for background launches
        defaults?.synchronize()
        return true
    }

    static func clearBaseURL() {
        defaults?.removeObject(forKey: baseURLKey)
        defaults?.synchronize()
    }
}
