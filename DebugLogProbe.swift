// DebugLogProbe.swift
// Philippe Achkar
// 2026-02-28

import Foundation
import os

enum DebugLogProbe {

    /// Call this once at app launch. It logs via:
    /// 1) print (stdout)
    /// 2) os.Logger (unified logging)
    /// 3) LogManager (your in-app logger)
    static func boot(_ msg: String,
                     file: String = #fileID,
                     function: String = #function,
                     line: Int = #line) {

        let stamp = ISO8601DateFormatter().string(from: Date())
        let payload = "[BOOT] \(stamp) \(msg) (\(file):\(line) \(function))"

        // 1) Xcode console stdout
        print(payload)

        // 2) Unified logging (viewable in Console app + sometimes Xcode)
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LoopFollow", category: "Debug")
        logger.debug("\(payload, privacy: .public)")

        // 3) Your app logger
        LogManager.shared.log(category: .general, message: payload)
    }
}
