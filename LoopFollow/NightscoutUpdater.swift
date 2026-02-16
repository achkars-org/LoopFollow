import Foundation
import UIKit

final class NightscoutUpdater {
    static let shared = NightscoutUpdater()
    private init() {}

    func refreshData() async throws {

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

        LogManager.shared.log(
            category: .general,
            message: "📥 [UPDATER] fetched mgdl=\(latest.mgdl) direction=\(latest.direction ?? "nil")"
        )

        // Convert mg/dL → mmol
        let mmol = Double(latest.mgdl) / 18.0182

        // Store previous before overwriting
        Storage.shared.previousGlucoseMmol.value = Storage.shared.currentGlucoseMmol.value
        Storage.shared.currentGlucoseMmol.value = mmol

        // Store trend arrow
        Storage.shared.trendArrow.value = NightscoutClient.shared.arrow(for: latest.direction)

        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        LogManager.shared.log(category: .general, message: "✅ [UPDATER] stored glucose in \(ms)ms")
    }
}
