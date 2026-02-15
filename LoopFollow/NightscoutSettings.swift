//
//  NightscoutSettings.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-13.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//


import Foundation
import Security

enum NightscoutSettings {
    private static let tokenKey = "nightscout_readable_token"

    static func setBaseURL(_ url: String) -> Bool {
        NightscoutConfigStore.setBaseURL(url)
    }

    static func getBaseURL() -> String? { NightscoutConfigStore.getBaseURL() }

    static func setToken(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return KeychainStore.set(t, for: tokenKey)
    }

    static func getToken() -> String? { KeychainStore.get(tokenKey) }
}
