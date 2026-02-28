// LFUnifiedLog.swift
// Philippe Achkar
// 2026-02-28

import Foundation
import os

enum LFUnifiedLog {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LoopFollow",
        category: "Debug"
    )

    static func debug(_ message: String) {
        log.debug("\(message, privacy: .public)")
    }
}
