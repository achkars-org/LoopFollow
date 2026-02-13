//
//  LoopFollowLiveActivityBundle.swift
//  LoopFollowLiveActivity
//
//  Created by Philippe Achkar on 2026-02-12.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import WidgetKit
import SwiftUI

@main
struct LoopFollowLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LoopFollowLiveActivity()
        LoopFollowLiveActivityControl()
        LoopFollowLiveActivityLiveActivity()
    }
}
