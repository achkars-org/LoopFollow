// LoopFollow
// DebugComplicationWidget.swift

#if DEBUG
    import SwiftUI
    import WidgetKit

    /// Pipeline diagnostics, Debug builds only. The top time is when the reading was
    /// taken; the bottom (↺) is when WidgetKit last rebuilt the timeline. If the top
    /// changes but ↺ does not, timeline reloads are not happening.
    struct DebugComplicationWidget: Widget {
        var body: some WidgetConfiguration {
            StaticConfiguration(kind: WatchWidgetKind.debug, provider: DebugTimelineProvider()) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.readingTime)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Text("↺ \(entry.builtTime)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .containerBackground(.fill.tertiary, for: .widget)
            }
            .configurationDisplayName("LoopFollow Debug")
            .description("Reading and refresh times for diagnosing complication updates.")
            .supportedFamilies([.accessoryRectangular])
        }
    }

    struct DebugEntry: TimelineEntry {
        let date: Date
        let readingTime: String
        let builtTime: String
    }

    struct DebugTimelineProvider: TimelineProvider {
        private static func timeString(_ date: Date?) -> String {
            guard let date else { return "--:--" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }

        private func entry() -> DebugEntry {
            DebugEntry(
                date: Date(),
                readingTime: Self.timeString(GlucoseSnapshotStore.shared.load()?.updatedAt),
                builtTime: Self.timeString(Date())
            )
        }

        func placeholder(in _: Context) -> DebugEntry {
            DebugEntry(date: Date(), readingTime: "--:--", builtTime: "--:--")
        }

        func getSnapshot(in _: Context, completion: @escaping (DebugEntry) -> Void) {
            completion(entry())
        }

        func getTimeline(in _: Context, completion: @escaping (Timeline<DebugEntry>) -> Void) {
            completion(Timeline(entries: [entry()], policy: .never))
        }
    }
#endif
