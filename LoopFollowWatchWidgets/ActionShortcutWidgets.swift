// LoopFollow
// ActionShortcutWidgets.swift

import SwiftUI
import WidgetKit

/// Static complications that open a remote command screen in one tap.
/// `Widget` requires a no-argument initializer, hence one small type per shortcut. Each
/// declares its configuration inline: a shared helper returning `some WidgetConfiguration`
/// trapped inside WidgetKit at launch and took the whole bundle down with it.
struct BolusShortcutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LoopFollowShortcut.bolus", provider: ActionShortcutProvider()) { _ in
            ActionShortcutView(title: "Bolus", systemImage: "syringe")
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WatchDeepLink.bolus.url)
        }
        .configurationDisplayName("LoopFollow Bolus")
        .description("Opens bolus entry.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct MealShortcutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LoopFollowShortcut.meal", provider: ActionShortcutProvider()) { _ in
            ActionShortcutView(title: "Meal", systemImage: "fork.knife")
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WatchDeepLink.meal.url)
        }
        .configurationDisplayName("LoopFollow Meal")
        .description("Opens meal entry.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct OverrideShortcutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LoopFollowShortcut.override", provider: ActionShortcutProvider()) { _ in
            ActionShortcutView(title: "Override", systemImage: "list.bullet")
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WatchDeepLink.override.url)
        }
        .configurationDisplayName("LoopFollow Override")
        .description("Opens override entry.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

private struct ActionShortcutView: View {
    @Environment(\.widgetFamily) private var family
    let title: String
    let systemImage: String

    var body: some View {
        if family == .accessoryCorner {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
                .widgetLabel(title)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .widgetAccentable()
            }
        }
    }
}

struct ActionShortcutEntry: TimelineEntry {
    let date: Date
}

/// The shortcut never changes, so it is drawn once and never reloaded.
struct ActionShortcutProvider: TimelineProvider {
    func placeholder(in _: Context) -> ActionShortcutEntry {
        ActionShortcutEntry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (ActionShortcutEntry) -> Void) {
        completion(ActionShortcutEntry(date: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<ActionShortcutEntry>) -> Void) {
        completion(Timeline(entries: [ActionShortcutEntry(date: Date())], policy: .never))
    }
}
