import Foundation
import UIKit

final class NightscoutUpdater {
    static let shared = NightscoutUpdater()
    private init() {}

    // Nightscout mg/dL <-> mmol/L
    private let mgdlPerMmol: Double = 18.0182

    func refreshData() async throws {

        let t0 = Date()
        LogManager.shared.log(category: .general, message: "🔄 [UPDATER] start")

        guard let baseURL = NightscoutSettings.getBaseURL() else {
            throw NSError(domain: "NightscoutUpdater", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Nightscout base URL is nil"
            ])
        }

        let token = NightscoutSettings.getToken()
        let tokenSet = (token?.isEmpty == false)

        LogManager.shared.log(
            category: .general,
            message: "🔎 [UPDATER] Nightscout config — url=\(baseURL) tokenSet=\(tokenSet)"
        )

        // -----------------------------
        // A) Glucose (existing behavior)
        // -----------------------------
        LogManager.shared.log(category: .general, message: "🌐 [UPDATER] calling NightscoutClient.fetchLatest()")

        let latest = try await NightscoutClient.shared.fetchLatest()

        LogManager.shared.log(
            category: .general,
            message: "📥 [UPDATER] fetched mgdl=\(latest.mgdl) direction=\(latest.direction ?? "nil")"
        )

        // Convert mg/dL → mmol
        let mmol = Double(latest.mgdl) / mgdlPerMmol

        // Store previous before overwriting
        Storage.shared.previousGlucoseMmol.value = Storage.shared.currentGlucoseMmol.value
        Storage.shared.currentGlucoseMmol.value = mmol

        // Store trend arrow
        Storage.shared.trendArrow.value = NightscoutClient.shared.arrow(for: latest.direction)

        LogManager.shared.log(category: .general, message: "✅ [UPDATER] stored glucose")

        // -----------------------------------------
        // B) Phase B: IOB / COB / Projected (device status)
        // -----------------------------------------
        do {
            LogManager.shared.log(category: .general, message: "🌐 [UPDATER] calling devicestatus (IOB/COB/Proj)")

            if let ds = try await fetchLatestDeviceStatus(baseURL: baseURL, token: token) {

                // Update Storage values for Live Activity
                Storage.shared.latestIOB.value = ds.iob
                Storage.shared.latestCOB.value = ds.cob
                Storage.shared.projectedMmol.value = ds.projectedMmol

                LogManager.shared.log(
                    category: .general,
                    message: """
                    ✅ [UPDATER] stored deviceStatus:
                    iob=\(ds.iob.map { String(format: "%.2f", $0) } ?? "nil")
                    cob=\(ds.cob.map { String(format: "%.0f", $0) } ?? "nil")
                    proj_mmol=\(ds.projectedMmol.map { String(format: "%.1f", $0) } ?? "nil")
                    units=\(ds.units)
                    """
                )
            } else {
                LogManager.shared.log(category: .general, message: "⚠️ [UPDATER] devicestatus empty (no updates for iob/cob/proj)")
            }
        } catch {
            // Don’t fail the entire refresh if Phase B fails — glucose is still valuable.
            LogManager.shared.log(category: .general, message: "⚠️ [UPDATER] devicestatus fetch/parse failed: \(error)")
        }

        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        LogManager.shared.log(category: .general, message: "✅ [UPDATER] done in \(ms)ms")
    }

    // MARK: - Device Status Fetch + Parse

    private struct DeviceStatusSnapshot {
        let iob: Double?
        let cob: Double?
        let projectedMmol: Double?
        let units: String  // "mg/dl" or "mmol"
    }

    private func fetchLatestDeviceStatus(baseURL: String, token: String?) async throws -> DeviceStatusSnapshot? {

        // Typical Nightscout endpoint
        // NOTE: Some setups use /api/v1/devicestatus (without .json). Both usually work.
        let urlString = "\(baseURL)/api/v1/devicestatus.json?count=1"
        guard var components = URLComponents(string: urlString) else {
            throw NSError(domain: "NightscoutUpdater", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid devicestatus URL"
            ])
        }

        // Support token-style auth (Nightscout "token" param) when token is not a classic api-secret
        if let token, !token.isEmpty, !looksLikeApiSecret(token) {
            var q = components.queryItems ?? []
            q.append(URLQueryItem(name: "token", value: token))
            components.queryItems = q
        }

        guard let url = components.url else {
            throw NSError(domain: "NightscoutUpdater", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unable to form devicestatus URL"
            ])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15

        // Support api-secret style auth
        if let token, !token.isEmpty, looksLikeApiSecret(token) {
            req.setValue(token, forHTTPHeaderField: "api-secret")
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse {
            LogManager.shared.log(category: .general, message: "📡 [UPDATER] devicestatus HTTP \(http.statusCode)")
        }

        // Parse JSON
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let arr = obj as? [[String: Any]], let first = arr.first else {
            return nil
        }

        // Units (default mg/dl)
        // Some payloads may not include this; mg/dl is the safest default.
        let units = (first["units"] as? String)?.lowercased() ?? "mg/dl"

        // IOB / COB commonly appear at the top-level in some Loop-style payloads,
        // or nested (openaps/loop). We’ll try multiple likely paths.
        let iob = extractDouble(first, keys: [
            ["iob"],                         // top-level
            ["loop", "iob"],                 // nested
            ["openaps", "iob", "iob"]         // openaps-style
        ])

        let cob = extractDouble(first, keys: [
            ["cob"],                         // top-level
            ["loop", "cob"],                 // nested
            ["openaps", "cob"]               // openaps-style
        ])

        // Predicted: we’re aiming for "predicted.values" array (as you showed in DeviceStatusLoop)
        let predictedLast = extractPredictedLast(first)

        // Convert predictedLast to mmol for Live Activity storage
        let projectedMmol: Double?
        if let predictedLast {
            if units == "mmol" {
                // Already mmol (per payload)
                projectedMmol = predictedLast
            } else {
                // mg/dl -> mmol
                projectedMmol = predictedLast / mgdlPerMmol
            }
        } else {
            projectedMmol = nil
        }

        return DeviceStatusSnapshot(
            iob: iob,
            cob: cob,
            projectedMmol: projectedMmol,
            units: units
        )
    }

    // MARK: - Helpers

    private func looksLikeApiSecret(_ token: String) -> Bool {
        // Many Nightscout api-secrets are 40 hex chars (SHA1).
        // If it looks like that, treat it as api-secret header.
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t.count == 40 else { return false }
        return t.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    private func extractDouble(_ root: [String: Any], keys: [[String]]) -> Double? {
        for path in keys {
            if let v = extractAny(root, path: path) {
                if let d = v as? Double { return d }
                if let i = v as? Int { return Double(i) }
                if let s = v as? String, let d = Double(s) { return d }
            }
        }
        return nil
    }

    private func extractPredictedLast(_ root: [String: Any]) -> Double? {
        // Try multiple likely shapes:
        // 1) predicted: { values: [Double] }
        // 2) loop: { predicted: { values: [...] } }
        // 3) openaps: { suggested: { predBGs: { IOB: [...], ZT: [...], COB: [...] } } } (we’ll pick the last of any array we find)
        if let predicted = extractAny(root, path: ["predicted"]) as? [String: Any],
           let values = predicted["values"] as? [Double],
           let last = values.last {
            return last
        }

        if let predicted = extractAny(root, path: ["loop", "predicted"]) as? [String: Any],
           let values = predicted["values"] as? [Double],
           let last = values.last {
            return last
        }

        // openaps-style: openaps.suggested.predBGs.<series> : [Double]
        if let predBGs = extractAny(root, path: ["openaps", "suggested", "predBGs"]) as? [String: Any] {
            for (_, v) in predBGs {
                if let arr = v as? [Double], let last = arr.last {
                    return last
                }
            }
        }

        return nil
    }

    private func extractAny(_ root: [String: Any], path: [String]) -> Any? {
        var cur: Any = root
        for key in path {
            guard let dict = cur as? [String: Any], let next = dict[key] else { return nil }
            cur = next
        }
        return cur
    }
}
