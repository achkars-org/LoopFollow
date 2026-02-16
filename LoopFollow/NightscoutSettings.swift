//
//  NightscoutSettings.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-13.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation
import Security
import UIKit

enum NightscoutSettings {
    private static let tokenKey = "nightscout_readable_token"

    // MARK: - Keychain logging helpers

    private static func keychainStatusDescription(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(status) (\(message))"
        }
        return "\(status)"
    }

    private static func log(_ message: String) {
        // If LogManager isn't available in this target, replace with print(...)
        LogManager.shared.log(category: .general, message: message)
    }

    // MARK: - Existing Base URL (App Group)

    static func setBaseURL(_ url: String) -> Bool {
        let ok = NightscoutConfigStore.setBaseURL(url)
        log("🌐 Nightscout baseURL set ok=\(ok) value='\(getBaseURL() ?? "nil")'")
        return ok
    }

    static func getBaseURL() -> String? {
        let url = NightscoutConfigStore.getBaseURL()
        log("🌐 Nightscout baseURL get value='\(url ?? "nil")'")
        return url
    }

    // MARK: - Token (Keychain)

    static func setToken(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            log("🔐 Nightscout token set rejected (empty/whitespace)")
            return false
        }

        let ok = KeychainStore.set(t, for: tokenKey)

        // Immediately read back to verify persistence + visibility
        let readBack = KeychainStore.get(tokenKey)

        log("🔐 Nightscout token set ok=\(ok) readBack=\(readBack == nil ? "nil" : "present") isProtectedDataAvailable=\(UIApplication.shared.isProtectedDataAvailable)")

        return ok
    }

    static func getToken() -> String? {
        let token = KeychainStore.get(tokenKey)

        // If nil, log context that often explains background failures
        if token == nil {
            // Attempt a raw SecItemCopyMatching for OSStatus (so we can see WHY)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: tokenKey,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            let statusDesc = keychainStatusDescription(status)

            log("🔐 Nightscout token get -> nil. SecItemCopyMatching status=\(statusDesc) isProtectedDataAvailable=\(UIApplication.shared.isProtectedDataAvailable)")
        } else {
            log("🔐 Nightscout token get -> present isProtectedDataAvailable=\(UIApplication.shared.isProtectedDataAvailable)")
        }

        return token
    }
}
