// LoopFollow
// WatchDeepLink.swift

import Foundation

/// Screens a complication can open directly in the Watch app.
enum WatchDeepLink: String, CaseIterable, Identifiable {
    case bolus
    case meal
    case override

    static let scheme = "loopfollowwatch"

    var id: String { rawValue }

    var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host, let link = WatchDeepLink(rawValue: host) else {
            return nil
        }
        self = link
    }
}
