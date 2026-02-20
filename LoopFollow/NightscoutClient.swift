import Foundation

final class NightscoutClient {
    static let shared = NightscoutClient()
    private init() {}

    struct LatestReading {
        let mgdl: Int
        let direction: String?
        let date: Date
    }

    // MARK: - Settings (Storage via NightscoutSettings)

    func getBaseURL() -> String? {
        NightscoutSettings.getBaseURL()
    }

    func getToken() -> String? {
        NightscoutSettings.getToken()
    }

    // MARK: - API

    func fetchLatest() async throws -> LatestReading {
        guard let base = NightscoutSettings.getBaseURL() else {
            throw NSError(
                domain: "NightscoutClient",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Nightscout URL not set"]
            )
        }

        var comps = URLComponents(string: "\(base)/api/v1/entries.json")
        comps?.queryItems = [
            URLQueryItem(name: "count", value: "1")
        ]

        // Token as query param (supported by many NS setups)
        // Only attach if present; some NS instances allow read access without token.
        if let token = NightscoutSettings.getToken(), !token.isEmpty {
            comps?.queryItems?.append(URLQueryItem(name: "token", value: token))
        }

        guard let url = comps?.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "NightscoutClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Nightscout HTTP \(http.statusCode)"]
            )
        }

        guard
            let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let first = arr.first,
            let sgv = first["sgv"] as? Int
        else {
            throw NSError(
                domain: "NightscoutClient",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected Nightscout response"]
            )
        }

        let dir = first["direction"] as? String

        let date: Date
        if let ms = first["date"] as? Double {
            date = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let msInt = first["date"] as? Int {
            date = Date(timeIntervalSince1970: Double(msInt) / 1000.0)
        } else {
            date = Date()
        }

        return LatestReading(mgdl: sgv, direction: dir, date: date)
    }

    // MARK: - Formatting

    func mmolString(from mgdl: Int) -> String {
        let mmol = Double(mgdl) / 18.0182
        return String(format: "%.1f", mmol)
    }

    func arrow(for direction: String?) -> String {
        switch direction {
        case "DoubleUp": return "⇈"
        case "SingleUp": return "↑"
        case "FortyFiveUp": return "↗︎"
        case "Flat": return "→"
        case "FortyFiveDown": return "↘︎"
        case "SingleDown": return "↓"
        case "DoubleDown": return "⇊"
        default: return ""
        }
    }
}
