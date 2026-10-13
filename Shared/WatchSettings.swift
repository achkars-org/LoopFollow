// LoopFollow
// WatchSettings.swift

import Foundation

/// Phone-owned settings the Watch app needs.
///
/// The iPhone and the Watch each have their own App Group container, so values the
/// phone writes to its App Group never reach the Watch. Instead the phone sends this
/// payload over WatchConnectivity and the Watch writes it into its own App Group,
/// where Watch code reads it through `LAAppGroupSettings`.
struct WatchSettings: Codable, Equatable {
    /// WatchConnectivity payload key.
    static let payloadKey = "settings"

    var lowMgdl: Double
    var highMgdl: Double
    var remoteEnabled: Bool
    var maxBolus: Double
    var maxCarbs: Double
    var overridePresets: [WatchOverridePreset]
    var nightscoutURL: String
    var nightscoutToken: String

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) throws -> WatchSettings {
        try JSONDecoder().decode(WatchSettings.self, from: data)
    }

    /// Persists every field into this device's App Group container.
    func applyToAppGroup() {
        LAAppGroupSettings.setThresholds(lowMgdl: lowMgdl, highMgdl: highMgdl)
        LAAppGroupSettings.setWatchRemoteEnabled(remoteEnabled)
        LAAppGroupSettings.setWatchMaxBolus(maxBolus)
        LAAppGroupSettings.setWatchMaxCarbs(maxCarbs)
        LAAppGroupSettings.setWatchOverridePresets(overridePresets)
        LAAppGroupSettings.setWatchNightscoutURL(nightscoutURL)
        LAAppGroupSettings.setWatchNightscoutToken(nightscoutToken)
    }

    /// Reads the values back from this device's App Group container.
    static func fromAppGroup() -> WatchSettings {
        let thresholds = LAAppGroupSettings.thresholdsMgdl()
        return WatchSettings(
            lowMgdl: thresholds.low,
            highMgdl: thresholds.high,
            remoteEnabled: LAAppGroupSettings.isWatchRemoteEnabled(),
            maxBolus: LAAppGroupSettings.watchMaxBolus(),
            maxCarbs: LAAppGroupSettings.watchMaxCarbs(),
            overridePresets: LAAppGroupSettings.watchOverridePresets(),
            nightscoutURL: LAAppGroupSettings.watchNightscoutURL(),
            nightscoutToken: LAAppGroupSettings.watchNightscoutToken()
        )
    }
}
