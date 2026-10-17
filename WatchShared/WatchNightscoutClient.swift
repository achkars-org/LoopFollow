// LoopFollow
// WatchNightscoutClient.swift

import Foundation

/// Fetches the latest reading straight from Nightscout, for the Watch app and the
/// complication, when the phone's pushes have not arrived. The URL and access token
/// come from the settings the phone sends over WatchConnectivity.
enum WatchNightscoutClient {
    enum Failure: Error {
        case notConfigured
        case notHTTPS
        case network(String)
        case empty
        case decode
    }

    /// Fetches the newest reading and records it in the shared history. The caller decides
    /// whether the snapshot is newer than what it already has and saves it.
    static func fetchLatest(completion: @escaping (Result<GlucoseSnapshot, Failure>) -> Void) {
        let urlString = LAAppGroupSettings.watchNightscoutURL()
        guard !urlString.isEmpty, let baseURL = URL(string: urlString) else {
            completion(.failure(.notConfigured))
            return
        }
        guard baseURL.scheme?.lowercased() == "https" else {
            completion(.failure(.notHTTPS))
            return
        }
        var request = URLRequest(url: entriesURL(base: baseURL, token: LAAppGroupSettings.watchNightscoutToken()))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            guard let data else {
                completion(.failure(.empty))
                return
            }
            completion(snapshot(from: data))
        }.resume()
    }

    /// Nightscout access tokens travel as the `token` query item.
    static func entriesURL(base: URL, token: String) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = "/api/v1/entries.json"
        var items = [URLQueryItem(name: "count", value: "1")]
        if !token.isEmpty {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items
        return components.url ?? base
    }

    static func snapshot(from data: Data) -> Result<GlucoseSnapshot, Failure> {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return .failure(.decode) }
        guard let entry = entries.first else { return .failure(.empty) }

        let updatedAt = Date(timeIntervalSince1970: entry.date / 1000)
        let history = WatchGlucoseHistory.load() ?? WatchGlucoseHistory(points: [])
        // Delta against the previous reading, if it is roughly one CGM interval back.
        let previous = history.points.last { $0.date < updatedAt.timeIntervalSince1970 }
        let delta = previous.flatMap { point -> Double? in
            guard updatedAt.timeIntervalSince1970 - point.date <= 2 * WatchRefreshPolicy.readingInterval else { return nil }
            return Double(entry.sgv - point.mgdl)
        } ?? 0
        history
            .appending(.init(date: updatedAt.timeIntervalSince1970, mgdl: entry.sgv), now: Date())
            .save()
        return .success(GlucoseSnapshot(
            glucose: Double(entry.sgv),
            delta: delta,
            trend: trend(from: entry.direction),
            updatedAt: updatedAt,
            iob: nil,
            cob: nil,
            projected: nil,
            unit: GlucoseSnapshotStore.shared.load()?.unit ?? .mgdl,
            isNotLooping: false
        ))
    }

    static func trend(from direction: String?) -> GlucoseSnapshot.Trend {
        switch direction {
        case "DoubleUp": return .upFast
        case "SingleUp": return .up
        case "FortyFiveUp": return .upSlight
        case "Flat": return .flat
        case "FortyFiveDown": return .downSlight
        case "SingleDown": return .down
        case "DoubleDown": return .downFast
        default: return .unknown
        }
    }

    /// One entry of `entries.json`.
    private struct Entry: Decodable {
        /// Glucose value in mg/dL.
        let sgv: Int
        /// Timestamp in milliseconds since epoch.
        let date: TimeInterval
        let direction: String?

        enum CodingKeys: String, CodingKey {
            case sgv, date, direction
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // sgv may arrive as Int or Double in some Nightscout versions.
            if let intValue = try? container.decode(Int.self, forKey: .sgv) {
                sgv = intValue
            } else {
                sgv = try Int(container.decode(Double.self, forKey: .sgv).rounded())
            }
            date = try container.decode(TimeInterval.self, forKey: .date)
            direction = try container.decodeIfPresent(String.self, forKey: .direction)
        }
    }
}
