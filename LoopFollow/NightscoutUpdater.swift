//
//  NightscoutUpdater.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-13.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//
import Foundation

final class NightscoutUpdater {
    static let shared = NightscoutUpdater()
    private init() {}

    func refreshAndUpdateLiveActivity() async throws {
        let latest = try await NightscoutClient.shared.fetchLatest()
        let mmol = NightscoutClient.shared.mmolString(from: latest.mgdl)
        let arrow = NightscoutClient.shared.arrow(for: latest.direction)

        LiveActivityManager.shared.update(glucoseText: mmol, trendText: arrow)
    }
}
