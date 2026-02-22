//
//  NightscoutSettings.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-13.
//

import Foundation

enum NightscoutSettings {
    
    // Legacy keys used by the refactor experiment
    private static let legacyTokenKey = "nightscout_readable_token"
    private static let legacyBaseURLKey = "nightscout_base_url" // only if it was ever stored in Keychain elsewhere
    
    // MARK: - Logging (LogManager + fallback)
    
    private static func log(_ msg: String) {
        LogManager.shared.log(category: .general, message: msg)
        print("NightscoutSettings:", msg)
    }
    
    // MARK: - Base URL (Storage)
    
    static func setBaseURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        
        guard let u = URL(string: trimmed), u.scheme?.hasPrefix("http") == true else {
            log("🌐 BaseURL set rejected (invalid) value='\(url)'")
            return false
        }
        
        Storage.shared.url.value = trimmed
        log("🌐 BaseURL set ok=true value='\(trimmed)'")
        return true
    }
    
    static func getBaseURL() -> String? {
        let raw = Storage.shared.url.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = raw.replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        let result = cleaned.isEmpty ? nil : cleaned
        log("🌐 BaseURL get value=\(result ?? "nil")")
        return result
    }
    
    // MARK: - Token (Storage)
    
    static func setToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log("🔐 Token set rejected (empty)")
            return false
        }
        
        Storage.shared.token.value = trimmed
        log("🔐 Token set ok=true len=\(trimmed.count)")
        return true
    }
    
    static func getToken() -> String? {
        let t = Storage.shared.token.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = t.isEmpty ? nil : t
        log("🔐 Token get \(result == nil ? "nil" : "OK (present)")")
        return result
    }
    
    // MARK: - One-time migration (legacy -> Storage)
    
    /// Call once at launch. Safe: only migrates if Storage is empty.
    static func migrateLegacyIfNeeded() {
        
        // --- 1️⃣ Token migration (Keychain -> Storage.shared.token)
        
        if Storage.shared.token.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty,
           let legacyToken = KeychainStore.get(legacyTokenKey),
           !legacyToken.isEmpty {
            
            Storage.shared.token.value = legacyToken
            log("🔁 Migrated legacy token Keychain('nightscout_readable_token') -> Storage.shared.token")
        }
        
        // --- 2️⃣ Base URL migration (App Group UserDefaults -> Storage.shared.url)
        
        if Storage.shared.url.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            
            let appGroupID = "group.com.2HEY366Q6J.LoopFollow"
            let baseURLKey = "nightscout.baseURL"
            
            if let defaults = UserDefaults(suiteName: appGroupID),
               let legacyURL = defaults.string(forKey: baseURLKey),
               !legacyURL.isEmpty {
                
                Storage.shared.url.value = legacyURL
                log("🔁 Migrated legacy baseURL AppGroup('\(baseURLKey)') -> Storage.shared.url")
            }
        }
    }
}
