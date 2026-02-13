//
//  GlucoseLiveActivityWidget.swift
//  LoopFollow
//
//  Created by Philippe Achkar on 2026-02-12.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct GlucoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseLiveActivityAttributes.self) { context in
            VStack(spacing: 6) {
                Text(context.attributes.title).font(.caption)
                HStack(spacing: 6) {
                    Text(context.state.glucoseText)
                        .font(.system(size: 36, weight: .bold))
                    Text(context.state.trendText)
                        .font(.headline)
                }
                Text(context.state.updatedAt, style: .time)
                    .font(.caption2)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 6) {
                        Text(context.state.glucoseText).font(.title2).bold()
                        Text(context.state.trendText).font(.headline)
                    }
                }
            } compactLeading: {
                Text(context.state.glucoseText).font(.caption).bold()
            } compactTrailing: {
                Text(context.state.trendText).font(.caption2)
            } minimal: {
                Text(context.state.glucoseText.prefix(2)).font(.caption2).bold()
            }
        }
    }
}
