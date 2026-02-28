// LoopFollow
// SAge.swift

import Foundation

extension MainViewController {
    // NS Sage Web Call
    func webLoadNSSage() {
        let lastDateString = dateTimeUtils.getDateTimeString(addingDays: -60)
        let currentTimeString = dateTimeUtils.getDateTimeString()

        let parameters: [String: String] = [
            "find[eventType]": NightscoutUtils.EventType.sage.rawValue,
            "find[created_at][$gte]": lastDateString,
            "find[created_at][$lte]": currentTimeString,
            "count": "1",
        ]

        NightscoutUtils.executeRequest(eventType: .sage, parameters: parameters) { (result: Result<[sageData], Error>) in
            switch result {
            case let .success(data):
                DispatchQueue.main.async {
                    self.updateSage(data: data)
                }
            case let .failure(error):
                LogManager.shared.log(category: .nightscout, message: "webLoadNSSage, failed to fetch data: \(error.localizedDescription)")
            }
        }
    }

    // NS Sage Response Processor
    func updateSage(data: [sageData]) {
        infoManager.clearInfoData(type: .sage)

        guard !data.isEmpty else { return }

        currentSage = data[0]

        // created_at is already a non-optional String in your model
        let lastSageString = data[0].created_at

        // Parse the ISO8601 timestamp
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [
            .withFullDate,
            .withTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]

        // Convert to epoch seconds and persist (only if parsing succeeds)
        if let t = iso.date(from: lastSageString)?.timeIntervalSince1970 {
            Storage.shared.sageInsertTime.value = t
        }

        // -- Auto-snooze CGM start ────────────────────────────────────────────────
        if Storage.shared.alarmConfiguration.value.autoSnoozeCGMStart {
            let nowEpoch = Date().timeIntervalSince1970

            // sageInsertTime is expected to be a non-optional TimeInterval
            let insertTime = Storage.shared.sageInsertTime.value

            // If the start is less than 2 h ago, snooze all alarms for the remainder of that 2-hour window.
            if nowEpoch - insertTime < 7200 {
                var cfg = Storage.shared.alarmConfiguration.value
                cfg.snoozeUntil = Date(timeIntervalSince1970: insertTime + 7200)
                Storage.shared.alarmConfiguration.value = cfg
            }
        }

        // Update UI "SAGE" duration string
        if let sageTime = iso.date(from: lastSageString)?.timeIntervalSince1970 {
            let now = dateTimeUtils.getNowTimeIntervalUTC()
            let secondsAgo = now - sageTime

            let durationFormatter = DateComponentsFormatter()
            durationFormatter.unitsStyle = .positional
            durationFormatter.allowedUnits = [.day, .hour]
            durationFormatter.zeroFormattingBehavior = [.pad]

            if let formattedDuration = durationFormatter.string(from: secondsAgo) {
                infoManager.updateInfoData(type: .sage, value: formattedDuration)
            }
        }
    }
}
