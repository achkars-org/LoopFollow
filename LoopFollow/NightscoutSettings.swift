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

    // MARK: - Logging (LogManager + fallback)

    private static func log(_ msg: String) {
        // Primary: in-app logs
        LogManager.shared.log(category: .general, message: msg)

        // Fallback: Xcode/device console (harmless duplication, very useful)
        print("NightscoutSettings:", msg)
    }

    private static func keychainStatusDescription(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(status) (\(message))"
        }
        return "\(status)"
    }

    // MARK: - Base URL (App Group)

    static func setBaseURL(_ url: String) -> Bool {
        let ok = NightscoutConfigStore.setBaseURL(url)
        log("🌐 BaseURL set ok=\(ok)")
        return ok
    }

    static func getBaseURL() -> String? {
        let url = NightscoutConfigStore.getBaseURL()
        log("🌐 BaseURL get value=\(url ?? "nil")")
        return url
    }

    // MARK: - Token (Keychain)

    static func setToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log("🔐 Token set rejected (empty)")
            return false
        }

        let ok = KeychainStore.set(trimmed, for: tokenKey)
        log("🔐 Token set ok=\(ok) len=\(trimmed.count)")

        // Immediately probe to capture accessibility + verify it’s really stored
        _ = probeTokenAndLog(context: "after setToken")

        return ok
    }

    static func getToken() -> String? {
        let token = KeychainStore.get(tokenKey)

        if token == nil {
            // This is the crucial “why?”
            _ = probeTokenAndLog(context: "getToken (KeychainStore.get returned nil)")
        } else {
            log("🔐 Token get OK (present)")
        }

        return token
    }

    // MARK: - Best diagnostic: Keychain probe

    /// Probes Keychain directly to retrieve OSStatus + attributes (esp. accessibility)
    /// and logs the result into LogManager.
    @discardableResult
    static func probeTokenAndLog(context: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            log("🔐 Keychain probe FAILED (\(context)) key='\(tokenKey)' status=\(keychainStatusDescription(status))")
            return nil
        }

        guard let dict = item as? [String: Any] else {
            log("🔐 Keychain probe OK but item not dict (\(context))")
            return nil
        }

        let account = (dict[kSecAttrAccount as String] as? String) ?? "nil"
        let accessible = (dict[kSecAttrAccessible as String] as? String) ?? "nil"
        let data = dict[kSecValueData as String] as? Data
        let dataLen = data?.count ?? 0
        let hasData = dataLen > 0

        log("🔐 Keychain probe OK (\(context)) account='\(account)' accessible='\(accessible)' hasData=\(hasData) dataLen=\(dataLen)")

        guard let dataUnwrapped = data else {
            log("🔐 Keychain probe decode FAILED (\(context)) no data")
            return nil
        }

        if let s = String(data: dataUnwrapped, encoding: .utf8) {
            log("🔐 Keychain probe decode OK (\(context)) strLen=\(s.count)")
            return s
        } else {
            log("🔐 Keychain probe decode FAILED (\(context)) data not UTF8")
            return nil
        }
    }
}
