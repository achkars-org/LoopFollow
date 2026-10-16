// LoopFollow
// ActionShortcutWidgets.swift

import SwiftUI
import WidgetKit

/// Static complications that open a remote command screen in one tap.
/// `Widget` requires a no-argument initializer, hence one small type per shortcut.
struct BolusShortcutWidget: Widget {
    var body: some WidgetConfiguration { ActionShortcut.configuration(for: .bolus) }
}

struct MealShortcutWidget: Widget {
    var body: some WidgetConfiguration { ActionShortcut.configuration(for: .meal) }
}

struct OverrideShortcutWidget: Widget {
    var body: some WidgetConfiguration { ActionShortcut.configuration(for: .override) }
}

private enum ActionShortcut {
    static func configuration(for link: WatchDeepLink) -> some WidgetConfiguration {
        StaticConfiguration(kind: "LoopFollowShortcut.\(link.rawValue)", provider: ActionShortcutProvider()) { _ in
            ActionShortcutView(title: title(for: link), systemImage: systemImage(for: link))
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(link.url)
        }
        .configurationDisplayName("LoopFollow \(title(for: link))")
        .description("Opens \(title(for: link).lowercased()) entry.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }

    private static func title(for link: WatchDeepLink) -> String {
        switch link {
        case .bolus: return "Bolus"
        case .meal: return "Meal"
        case .override: return "Override"
        }
    }

    private static func systemImage(for link: WatchDeepLink) -> String {
        switch link {
        case .bolus: return "syringe"
        case .meal: return "fork.knife"
        case .override: return "list.bullet"
        }
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
