// WatchAlertManager.swift
// LoopFollowWatch Watch App
//
// STUB — generated from design session, ready for integration.
// See DESIGN.md for rationale and CHANGES.md for injection points.

import Foundation
import UserNotifications
import os.log

private let alertLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "com.loopfollow.watch",
    category: "WatchAlert"
)

extension Notification.Name {
    static let showSnoozeSheet = Notification.Name("WatchShowSnoozeSheet")
}

// MARK: - Alert type

enum WatchAlertType: String, CaseIterable {
    case lowBG, urgentLow, highBG, fastDrop, fastRise

    var title: String {
        switch self {
        case .lowBG:     return "⚠️ Low BG"
        case .urgentLow: return "🚨 Urgent Low"
        case .highBG:    return "⚠️ High BG"
        case .fastDrop:  return "⬇️ Dropping Fast"
        case .fastRise:  return "⬆️ Rising Fast"
        }
    }

    var displayName: String {
        switch self {
        case .lowBG:     return "Low BG"
        case .urgentLow: return "Urgent Low"
        case .highBG:    return "High BG"
        case .fastDrop:  return "Fast Drop"
        case .fastRise:  return "Fast Rise"
        }
    }

    func body(bg: Double, delta: Double?) -> String {
        let bgStr = "\(Int(bg))"
        switch self {
        case .lowBG, .urgentLow, .highBG: return bgStr
        case .fastDrop: return delta.map { "\(bgStr) · \(Int($0))/min" } ?? bgStr
        case .fastRise: return delta.map { "\(bgStr) · +\(Int($0))/min" } ?? bgStr
        }
    }

    var cooldownKey: String    { "watchAlertCooldown_\(rawValue)" }
    var snoozeKey: String      { "watchSnoozeUntil_\(rawValue)" }
    var notificationID: String { "lf-alert-\(rawValue)" }
}

// MARK: - Thresholds
// TODO: Wire to LAAppGroupSettings or App Group shared container to mirror iPhone settings.

private struct WatchThresholds {
    var low: Double       = 70
    var urgentLow: Double = 55
    var high: Double      = 180
    var dropRate: Double  = 2.0   // mg/dL per minute
    var riseRate: Double  = 2.0
}

// MARK: - Manager

final class WatchAlertManager: NSObject {

    static let shared = WatchAlertManager()
    private override init() { super.init() }

    private let thresholds = WatchThresholds()
    private let settings   = WatchAppSettings.shared

    private let globalSnoozeKey = "watchGlobalSnoozeUntil"

    // MARK: - Snooze

    /// Returns true if this alert type is currently suppressed (global OR per-type snooze active).
    func isSnoozed(for type: WatchAlertType) -> Bool {
        let now     = Date().timeIntervalSince1970
        let global  = UserDefaults.standard.double(forKey: globalSnoozeKey)
        let perType = UserDefaults.standard.double(forKey: type.snoozeKey)
        return now < global || now < perType
    }

    /// Returns the latest active snooze expiry for this type (global or per-type), or nil.
    func snoozeUntil(for type: WatchAlertType) -> Date? {
        let now     = Date().timeIntervalSince1970
        let global  = UserDefaults.standard.double(forKey: globalSnoozeKey)
        let perType = UserDefaults.standard.double(forKey: type.snoozeKey)
        let until   = max(global, perType)
        return until > now ? Date(timeIntervalSince1970: until) : nil
    }

    /// Snooze. Pass nil type for global snooze; pass a specific type for per-type snooze.
    func snooze(minutes: Int, type: WatchAlertType?) {
        let until = Date().timeIntervalSince1970 + Double(minutes * 60)
        if let type = type {
            UserDefaults.standard.set(until, forKey: type.snoozeKey)
            os_log("WatchAlertManager: snoozed %{public}@ for %d min",
                   log: alertLog, type: .info, type.rawValue, minutes)
        } else {
            UserDefaults.standard.set(until, forKey: globalSnoozeKey)
            os_log("WatchAlertManager: snoozed all for %d min", log: alertLog, type: .info, minutes)
        }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Cancel snooze. Nil clears global + all per-type; specific type clears only that type.
    func cancelSnooze(type: WatchAlertType?) {
        if let type = type {
            UserDefaults.standard.set(0, forKey: type.snoozeKey)
        } else {
            UserDefaults.standard.set(0, forKey: globalSnoozeKey)
            WatchAlertType.allCases.forEach {
                UserDefaults.standard.set(0, forKey: $0.snoozeKey)
            }
        }
        os_log("WatchAlertManager: snooze cancelled", log: alertLog, type: .info)
    }

    // MARK: - Dismiss

    /// Dismiss = remove delivered notification banner. No cooldown change. Alert will re-fire on normal schedule.
    func dismiss(type: WatchAlertType) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [type.notificationID])
        os_log("WatchAlertManager: dismissed %{public}@", log: alertLog, type: .info, type.rawValue)
    }

    // MARK: - Setup (call once from applicationDidFinishLaunching)

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge]
        ) { granted, _ in
            os_log("WatchAlertManager: permission granted=%d", log: alertLog, type: .info, granted)
        }
    }

    private func registerNotificationCategories() {
        let dismiss = UNNotificationAction(
            identifier: "DISMISS_ALERT",
            title: "Dismiss",
            options: [.destructive]
        )
        let snooze = UNNotificationAction(
            identifier: "SNOOZE_ALERT",
            title: "Snooze…",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "GLUCOSE_ALERT",
            actions: [snooze, dismiss],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Check (main entry point — call from both WC and background refresh paths)

    func checkAndAlert(snapshot: GlucoseSnapshot) {
        let bg    = snapshot.glucose
        // TODO: Confirm whether snapshot.delta is per-minute or per-5-min and adjust deltaRate accordingly.
        let delta = snapshot.deltaRate

        // UrgentLow takes full priority — nothing else fires this cycle if triggered.
        let urgentTriggered = bg < thresholds.urgentLow
        evaluate(.urgentLow, bg: bg, delta: delta, triggered: urgentTriggered)
        guard !urgentTriggered else { return }

        evaluate(.lowBG,    bg: bg, delta: delta, triggered: bg < thresholds.low)
        evaluate(.highBG,   bg: bg, delta: delta, triggered: bg > thresholds.high)
        evaluate(.fastDrop, bg: bg, delta: delta, triggered: delta.map { $0 < -thresholds.dropRate } ?? false)
        evaluate(.fastRise, bg: bg, delta: delta, triggered: delta.map { $0 > thresholds.riseRate } ?? false)
    }

    // MARK: - Private

    private func evaluate(_ type: WatchAlertType, bg: Double, delta: Double?, triggered: Bool) {
        guard triggered, !isSnoozed(for: type) else { return }

        let now       = Date().timeIntervalSince1970
        let lastFired = UserDefaults.standard.double(forKey: type.cooldownKey)
        guard now - lastFired >= settings.cooldown(for: type) else { return }

        fire(type: type, bg: bg, delta: delta)
        UserDefaults.standard.set(now, forKey: type.cooldownKey)
    }

    private func fire(type: WatchAlertType, bg: Double, delta: Double?) {
        let content = UNMutableNotificationContent()
        content.title              = type.title
        content.body               = type.body(bg: bg, delta: delta)
        content.sound              = nil          // haptic only — no audio
        content.interruptionLevel  = (type == .urgentLow) ? .timeSensitive : .active
        content.categoryIdentifier = "GLUCOSE_ALERT"

        let request = UNNotificationRequest(
            identifier: type.notificationID,   // stable ID — replaces any pending same-type alert
            content: content,
            trigger: nil                        // immediate delivery
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                os_log("WatchAlertManager: failed %{public}@ — %{public}@",
                       log: alertLog, type: .error, type.rawValue, error.localizedDescription)
            } else {
                os_log("WatchAlertManager: fired %{public}@ bg=%d",
                       log: alertLog, type: .info, type.rawValue, Int(bg))
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension WatchAlertManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let typeRaw   = response.notification.request.identifier
            .replacingOccurrences(of: "lf-alert-", with: "")
        let alertType = WatchAlertType(rawValue: typeRaw)

        switch response.actionIdentifier {
        case "DISMISS_ALERT":
            if let type = alertType { dismiss(type: type) }

        case "SNOOZE_ALERT":
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showSnoozeSheet,
                    object: nil,
                    userInfo: alertType.map { ["alertType": $0.rawValue] }
                )
            }
        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge])
    }
}
