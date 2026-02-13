//
//  LoopFollowLiveActivityLiveActivity.swift
//  LoopFollowLiveActivity
//
//  Created by Philippe Achkar on 2026-02-12.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LoopFollowLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct LoopFollowLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LoopFollowLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension LoopFollowLiveActivityAttributes {
    fileprivate static var preview: LoopFollowLiveActivityAttributes {
        LoopFollowLiveActivityAttributes(name: "World")
    }
}

extension LoopFollowLiveActivityAttributes.ContentState {
    fileprivate static var smiley: LoopFollowLiveActivityAttributes.ContentState {
        LoopFollowLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: LoopFollowLiveActivityAttributes.ContentState {
         LoopFollowLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: LoopFollowLiveActivityAttributes.preview) {
   LoopFollowLiveActivityLiveActivity()
} contentStates: {
    LoopFollowLiveActivityAttributes.ContentState.smiley
    LoopFollowLiveActivityAttributes.ContentState.starEyes
}
