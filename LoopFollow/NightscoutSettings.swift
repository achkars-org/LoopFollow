//
//  NightscoutSettings.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-13.
//

import Foundation
import Security

enum NightscoutSettings {

    private static let tokenKey = "nightscout_readable_token"

    // MARK: - Keychain status helper

    private static func keychainStatusDescription(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(status) (\(message))"
        }
        return "\(status)"
    }

    private static func log(_ message: String) {
        print("NightscoutSettings:", message)
        // If LogManager exists in this target and you want it:
        // LogManager.shared.log(category: .general, message: message)
    }

    // MARK: - Base URL

    static func setBaseURL(_ url: String) -> Bool {
        let ok = NightscoutConfigStore.setBaseURL(url)
        log("BaseURL set ok=\(ok)")
        return ok
    }

    static func getBaseURL() -> String? {
        let url = NightscoutConfigStore.getBaseURL()
        log("BaseURL get value=\(url ?? "nil")")
        return url
    }

    // MARK: - Token (Keychain)

    static func setToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log("Token set rejected (empty)")
            return false
        }

        let ok = KeychainStore.set(trimmed, for: tokenKey)
        log("Token set ok=\(ok)")

        return ok
    }

    static func getToken() -> String? {
        let token = KeychainStore.get(tokenKey)

        if token == nil {
            // Perform raw SecItemCopyMatching to get OSStatus
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: tokenKey,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)

            log("Token get FAILED. SecItemCopyMatching status = \(keychainStatusDescription(status))")
        } else {
            log("Token get SUCCESS")
        }

        return token
    }
}
