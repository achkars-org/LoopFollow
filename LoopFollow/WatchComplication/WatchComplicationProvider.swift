// WatchComplicationProvider.swift
// Philippe Achkar
// 2026-03-10

import ClockKit
import Foundation
import os.log

private let watchLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "com.loopfollow.watch",
    category: "Watch"
)

final class WatchComplicationProvider: NSObject, CLKComplicationDataSource {

    // MARK: - Complication Descriptors

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "LoopFollowGlucose",
                displayName: "LoopFollow",
                supportedFamilies: [
                    .graphicCircular,
                    .graphicCorner
                ]
            )
        ]
        handler(descriptors)
    }

    // MARK: - Timeline

    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        guard let snapshot = GlucoseSnapshotStore.shared.load() else {
            os_log("WatchComplicationProvider: no snapshot available", log: watchLog, type: .debug)
            handler(nil)
            return
        }

        guard snapshot.age < 900 else {
            os_log("WatchComplicationProvider: snapshot stale (%d s)", log: watchLog, type: .debug, Int(snapshot.age))
            handler(staleEntry(for: complication))
            return
        }

        let template = ComplicationEntryBuilder.template(for: complication.family, snapshot: snapshot)
        let entry = template.map {
            CLKComplicationTimelineEntry(date: snapshot.updatedAt, complicationTemplate: $0)
        }
        handler(entry)
    }

    func getTimelineEndDate(
        for complication: CLKComplication,
        withHandler handler: @escaping (Date?) -> Void
    ) {
        // Expire timeline 15 minutes after last reading
        // so Watch does not display indefinitely stale data
        if let snapshot = GlucoseSnapshotStore.shared.load() {
            handler(snapshot.updatedAt.addingTimeInterval(900))
        } else {
            handler(nil)
        }
    }

    func getPrivacyBehavior(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void
    ) {
        // Glucose is sensitive — hide on locked watch face
        handler(.hideOnLockScreen)
    }

    // MARK: - Placeholder

    func getLocalizableSampleTemplate(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTemplate?) -> Void
    ) {
        handler(ComplicationEntryBuilder.placeholderTemplate(for: complication.family))
    }

    // MARK: - Private

    private func staleEntry(for complication: CLKComplication) -> CLKComplicationTimelineEntry? {
        let template = ComplicationEntryBuilder.staleTemplate(for: complication.family)
        return template.map {
            CLKComplicationTimelineEntry(date: Date(), complicationTemplate: $0)
        }
    }
}
