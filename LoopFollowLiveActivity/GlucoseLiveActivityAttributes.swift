import Foundation
import ActivityKit

struct GlucoseLiveActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {

        // Core glucose
        var glucoseMmol: Double?
        var previousGlucoseMmol: Double?
        var trend: String?

        // Treatments
        var iob: Double?
        var cob: Double?

        // Prediction
        var projectedMmol: Double?

        // Timestamp
        var updatedAt: Date

        // Debug / health
        var seq: Int
        var debug: String
        var updatedAtEpoch: Int
    }

    var title: String
}
