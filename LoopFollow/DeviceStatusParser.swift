//
//  DeviceStatusParser.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-17.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Foundation

enum DeviceStatusParser {
    static func extractLoopIOBCOB(from json: Any) -> (iob: Double?, cob: Double?) {
        guard
            let arr = json as? [[String: AnyObject]],
            let first = arr.first,
            let loop = first["loop"] as? [String: AnyObject]
        else { return (nil, nil) }

        // These keys match your DeviceStatusLoop.swift usage.
        let iob = (loop["iob"] as? Double) ?? (loop["iob"] as? NSNumber)?.doubleValue
        let cob = (loop["cob"] as? Double) ?? (loop["cob"] as? NSNumber)?.doubleValue
        return (iob, cob)
    }
}
