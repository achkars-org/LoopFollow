// LoopFollow
// WatchSettingsTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct WatchSettingsTests {
    private let sample = WatchSettings(
        lowMgdl: 72,
        highMgdl: 190,
        remoteEnabled: true,
        maxBolus: 4.5,
        maxCarbs: 80,
        overridePresets: [
            WatchOverridePreset(name: "Exercise", symbol: "🏃", durationSeconds: 3600),
            WatchOverridePreset(name: "Sick", symbol: nil, durationSeconds: 0),
        ],
        nightscoutURL: "https://example.nightscout.test",
        nightscoutToken: "token-123"
    )

    @Test("#settings survive the WatchConnectivity encoding")
    func encodedRoundTrip() throws {
        let decoded = try WatchSettings.decoded(from: sample.encoded())
        #expect(decoded == sample)
    }

    @Test("#applying to the App Group and reading back yields the same settings")
    func appGroupRoundTrip() {
        let previous = WatchSettings.fromAppGroup()
        defer { previous.applyToAppGroup() }

        sample.applyToAppGroup()
        #expect(WatchSettings.fromAppGroup() == sample)
    }

    @Test("#a malformed payload is rejected rather than half-applied")
    func malformedPayloadThrows() {
        #expect(throws: (any Error).self) {
            try WatchSettings.decoded(from: Data("{\"lowMgdl\":70}".utf8))
        }
    }
}
