// LoopFollow
// BGTask.swift

import Foundation

extension MainViewController {
    func scheduleBGTask(initialDelay: TimeInterval = 2) {
        let firstRun = Date().addingTimeInterval(initialDelay)
        TaskScheduler.shared.scheduleTask(id: .fetchBG, nextRun: firstRun) { [weak self] in
            guard let self = self else { return }
            self.bgTaskAction()
        }
    }

  func bgTaskAction() {
    // If anything goes wrong, try again in 60 seconds.
    TaskScheduler.shared.rescheduleTask(
        id: .fetchBG,
        to: Date().addingTimeInterval(60)
    )

    // Suppress polling if a silent push was received recently (APNs effectively active).
    if LASilentPushGate.shouldSuppressPolling(windowSeconds: 300) {
        let age = Int(LASilentPushGate.secondsSinceLastSilentPush() ?? -1)
        LogManager.shared.log(category: .liveactivities, message: "[POLL] suppressed (silentPushAge=\(age)s)")
        return
    }

    // ... existing logic unchanged ...
    if Storage.shared.shareUserName.value == "",
       Storage.shared.sharePassword.value == "",
       !IsNightscoutEnabled()
    {
        return
    }

    if Storage.shared.shareUserName.value != "",
       Storage.shared.sharePassword.value != ""
    {
        webLoadDexShare()
    } else {
        webLoadNSBGData()
    }
}
}
