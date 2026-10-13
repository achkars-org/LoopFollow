// LoopFollow
// AppGroupIDTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct AppGroupIDTests {
    @Test("#the main app bundle ID is left alone")
    func mainApp() {
        #expect(AppGroupID.stripLikelyExtensionSuffixes(from: "com.ABC.LoopFollow") == "com.ABC.LoopFollow")
    }

    @Test("#Live Activity extension resolves to the app")
    func liveActivity() {
        #expect(AppGroupID.stripLikelyExtensionSuffixes(from: "com.ABC.LoopFollow2.LoopFollowLAExtension") == "com.ABC.LoopFollow2")
    }

    @Test("#Watch app resolves to the app")
    func watchApp() {
        #expect(AppGroupID.stripLikelyExtensionSuffixes(from: "com.ABC.LoopFollow.watchkitapp") == "com.ABC.LoopFollow")
    }

    @Test("#Watch widget extension resolves through both suffixes")
    func watchWidgets() {
        #expect(AppGroupID.stripLikelyExtensionSuffixes(from: "com.ABC.LoopFollow3.watchkitapp.widgets") == "com.ABC.LoopFollow3")
    }
}
