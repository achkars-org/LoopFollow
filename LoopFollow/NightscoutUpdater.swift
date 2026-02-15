import Foundation
import UIKit

final class NightscoutUpdater {
    static let shared = NightscoutUpdater()
    private init() {}

    func refreshAndUpdateLiveActivity() async throws {
        let t0 = Date()
        LogManager.shared.log(category: .general, message: "🔄 [UPDATER] start")

        let baseURL = NightscoutSettings.getBaseURL()
        let tokenSet = (NightscoutSettings.getToken()?.isEmpty == false)

        LogManager.shared.log(
            category: .general,
            message: "🔎 [UPDATER] Nightscout config — url=\(baseURL ?? "nil") tokenSet=\(tokenSet)"
        )

        guard baseURL != nil else {
            throw NSError(domain: "NightscoutUpdater", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Nightscout base URL is nil"
            ])
        }

        LogManager.shared.log(category: .general, message: "🌐 [UPDATER] calling NightscoutClient.fetchLatest()")

        let latest = try await NightscoutClient.shared.fetchLatest()

        // ✅ Only log fields we know exist
        LogManager.shared.log(category: .general,
                              message: "📥 [UPDATER] fetched mgdl=\(latest.mgdl) direction=\(latest.direction ?? "nil")")

        let mmol = NightscoutClient.shared.mmolString(from: latest.mgdl)
        let arrow = NightscoutClient.shared.arrow(for: latest.direction)

        LogManager.shared.log(category: .general,
                              message: "🟩 [UPDATER] updating Live Activity mmol=\(mmol) arrow=\(arrow)")

        LiveActivityManager.shared.update(glucoseText: mmol, trendText: arrow)

        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        LogManager.shared.log(category: .general,
                              message: "✅ [UPDATER] done in \(ms)ms")
    }
}
