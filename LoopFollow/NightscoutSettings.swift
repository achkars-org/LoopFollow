//
//  NightscoutSettings.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-13.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//


import Foundation

enum NightscoutSettings {
    private static let urlKey = "nightscout_base_url"
    private static let tokenKey = "nightscout_readable_token"

    static func setBaseURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        guard let u = URL(string: trimmed), u.scheme?.hasPrefix("http") == true else { return false }
        return KeychainStore.set(trimmed, for: urlKey)
    }

    static func getBaseURL() -> String? { KeychainStore.get(urlKey) }

    static func setToken(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return KeychainStore.set(t, for: tokenKey)
    }

    static func getToken() -> String? { KeychainStore.get(tokenKey) }
}