import Foundation

final class NightscoutUpdater {
    static let shared = NightscoutUpdater()
    private init() {}

    // Nightscout mg/dL <-> mmol/L
    private let mgdlPerMmol: Double = 18.0182

    func refreshData() async throws {
        let t0 = Date()
        LogManager.shared.log(category: .liveactivities, message: "[UPDATER] refresh start")

        guard let baseURL = NightscoutSettings.getBaseURL() else {
            throw NSError(domain: "NightscoutUpdater", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Nightscout base URL is nil"
            ])
        }

        let token = NightscoutSettings.getToken()
        let tokenSet = (token?.isEmpty == false)

        LogManager.shared.log(
            category: .liveactivities,
            message: "[UPDATER] config urlSet=true tokenSet=\(tokenSet)"
        )

        // A) Glucose
        let latest = try await NightscoutClient.shared.fetchLatest()
        LogManager.shared.log(
            category: .liveactivities,
            message: "[UPDATER] latest mgdl=\(latest.mgdl) direction=\(latest.direction ?? "nil")"
        )

        // Convert mg/dL → mmol and store previous before overwriting current
        let mmol = Double(latest.mgdl) / mgdlPerMmol
        Storage.shared.previousGlucoseMmol.value = Storage.shared.currentGlucoseMmol.value
        Storage.shared.currentGlucoseMmol.value = mmol

        // Store trend arrow (string)
        Storage.shared.trendArrow.value = NightscoutClient.shared.arrow(for: latest.direction)

        // B) IOB / COB / Projected (deviceStatus)
        do {
            if let ds = try await fetchLatestDeviceStatus(baseURL: baseURL, token: token) {
                Storage.shared.latestIOB.value = ds.iob
                Storage.shared.latestCOB.value = ds.cob
                Storage.shared.projectedMmol.value = ds.projectedMmol

                LogManager.shared.log(
                    category: .liveactivities,
                    message: "[UPDATER] deviceStatus iob=\(ds.iob.map { String(format: "%.2f", $0) } ?? "nil") cob=\(ds.cob.map { String(format: "%.0f", $0) } ?? "nil") proj=\(ds.projectedMmol.map { String(format: "%.1f", $0) } ?? "nil") units=\(ds.units)"
                )
            } else {
                LogManager.shared.log(category: .liveactivities, message: "[UPDATER] deviceStatus empty")
            }
        } catch {
            // Don’t fail the entire refresh if deviceStatus fails — glucose is still valuable.
            LogManager.shared.log(category: .liveactivities, message: "[UPDATER] deviceStatus failed: \(error)")
        }

        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        LogManager.shared.log(category: .liveactivities, message: "[UPDATER] refresh done ms=\(ms)")
    }

    // MARK: - Device Status Fetch + Parse

    private struct DeviceStatusSnapshot {
        let iob: Double?
        let cob: Double?
        let projectedMmol: Double?
        let units: String // "mg/dl" or "mmol"
    }

    private func fetchLatestDeviceStatus(baseURL: String, token: String?) async throws -> DeviceStatusSnapshot? {
        let urlString = "\(baseURL)/api/v1/devicestatus.json?count=1"
        guard var components = URLComponents(string: urlString) else {
            throw NSError(domain: "NightscoutUpdater", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid devicestatus URL"
            ])
        }

        // Support token-style auth when token is not a classic api-secret
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
            LogManager.shared.log(category: .liveactivities, message: "[UPDATER] devicestatus HTTP \(http.statusCode)")
        }

        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let arr = obj as? [[String: Any]], let first = arr.first else {
            return nil
        }

        // Units (default mg/dl)
        let units = (first["units"] as? String)?.lowercased() ?? "mg/dl"

        // IOB / COB can appear in multiple shapes depending on uploader/client
        let iob = extractDouble(first, keys: [
            ["iob"],
            ["loop", "iob"],
            ["openaps", "iob", "iob"]
        ])

        let cob = extractDouble(first, keys: [
            ["cob"],
            ["loop", "cob"],
            ["openaps", "cob"]
        ])

        // Projected: take the last value from likely prediction arrays
        let predictedLast = extractPredictedLast(first)

        let projectedMmol: Double?
        if let predictedLast {
            projectedMmol = (units == "mmol") ? predictedLast : (predictedLast / mgdlPerMmol)
        } else {
            projectedMmol = nil
        }

        return DeviceStatusSnapshot(iob: iob, cob: cob, projectedMmol: projectedMmol, units: units)
    }

    // MARK: - Helpers

    private func looksLikeApiSecret(_ token: String) -> Bool {
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
