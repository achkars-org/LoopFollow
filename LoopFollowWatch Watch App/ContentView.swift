// LoopFollow
// ContentView.swift

import Combine
import SwiftUI
import WatchConnectivity
import WatchKit

// MARK: - Root view

struct ContentView: View {
    @StateObject private var model = WatchViewModel()
    @State private var showSettings = false
    @State private var showRemote = false
    @State private var showSnoozeStatus = false
    @State private var deepLink: WatchDeepLink?

    var body: some View {
        TabView {
            GlucoseView(model: model)
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 8) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")

                        if model.remoteEnabled {
                            Button { showRemote = true } label: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remote Commands")
                        }

                        if model.isSnoozed {
                            Button { showSnoozeStatus = true } label: {
                                Image(systemName: "bell.slash.fill")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Snooze")
                        }
                    }
                    .padding([.top, .trailing], 4)
                }
                .sheet(isPresented: $showRemote) {
                    NavigationStack { WatchRemoteCommandsView(snapshot: model.snapshot) }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack { WatchAlertSettingsView(model: model) }
                }
                .sheet(isPresented: $showSnoozeStatus) {
                    SnoozeStatusView(model: model, isPresented: $showSnoozeStatus)
                }

            GlucoseChartView(points: model.history, unit: model.snapshot?.unit ?? .mgdl)

            StatsPageView(stats: model.stats, unit: model.snapshot?.unit ?? .mgdl)

            ForEach(model.pages.indices, id: \.self) { idx in
                DataGridPage(slots: model.pages[idx], snapshot: model.snapshot)
            }
        }
        .tabViewStyle(.page)
        .sheet(item: $deepLink) { link in
            NavigationStack { remoteView(for: link) }
        }
        .onOpenURL { url in
            // Shortcut complications land on their remote screen; without remote
            // commands configured they simply open the app.
            guard let link = WatchDeepLink(url: url), LAAppGroupSettings.isWatchRemoteEnabled() else { return }
            showRemote = false
            showSettings = false
            deepLink = link
        }
        .onAppear {
            model.refresh()
            // Foreground reloads do not count against the complication budget.
            WatchSessionReceiver.shared.reloadComplications()
        }
    }
}

extension ContentView {
    @ViewBuilder
    private func remoteView(for link: WatchDeepLink) -> some View {
        switch link {
        case .bolus: WatchBolusCommandView(snapshot: model.snapshot)
        case .meal: WatchMealCommandView()
        case .override: WatchOverridePickerView()
        }
    }
}

// MARK: - View model

final class WatchViewModel: ObservableObject {
    @Published var snapshot: GlucoseSnapshot?
    @Published var selectedSlots: [LiveActivitySlotOption] = LAAppGroupSettings.watchSelectedSlots()
    @Published var showSnoozeSheet = false
    @Published var pendingSnoozeType: WatchAlertType?
    @Published var isSnoozed = false
    @Published var snoozeUntil: Date?
    @Published var hasActiveAlert = false
    @Published var remoteEnabled = LAAppGroupSettings.isWatchRemoteEnabled()
    @Published var history: [WatchGlucoseHistory.Point] = WatchGlucoseHistory.load()?.points ?? []
    @Published var stats: WatchStatsSummary? = WatchStatsSummary.load()

    private var timer: Timer?
    private var notificationObserver: Any?
    private var snoozeSheetObserver: Any?
    private var settingsObserver: Any?

    init() {
        snapshot = GlucoseSnapshotStore.shared.load()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        notificationObserver = NotificationCenter.default.addObserver(
            forName: WatchSessionReceiver.snapshotReceivedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let s = notification.userInfo?["snapshot"] as? GlucoseSnapshot {
                self?.update(snapshot: s)
            } else {
                self?.refresh()
            }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: WatchSessionReceiver.settingsRefreshedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        snoozeSheetObserver = NotificationCenter.default.addObserver(
            forName: .showSnoozeSheet,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let typeRaw = notification.userInfo?["alertType"] as? String
            self?.pendingSnoozeType = typeRaw.flatMap { WatchAlertType(rawValue: $0) }
            self?.showSnoozeSheet = true
        }
    }

    deinit {
        timer?.invalidate()
        if let obs = notificationObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = snoozeSheetObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = settingsObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func refresh() {
        if let loaded = GlucoseSnapshotStore.shared.load() {
            snapshot = loaded
        }
        selectedSlots = LAAppGroupSettings.watchSelectedSlots()
        isSnoozed = WatchAlertManager.shared.isGloballySnoozed
        snoozeUntil = WatchAlertManager.shared.globalSnoozeExpiryDate
        hasActiveAlert = snapshot.map { WatchAlertManager.shared.hasActiveAlert(for: $0) } ?? false
        remoteEnabled = LAAppGroupSettings.isWatchRemoteEnabled()
        history = WatchGlucoseHistory.load()?.points ?? []
        stats = WatchStatsSummary.load()
    }

    func update(snapshot: GlucoseSnapshot) {
        self.snapshot = snapshot
        selectedSlots = LAAppGroupSettings.watchSelectedSlots()
        hasActiveAlert = WatchAlertManager.shared.hasActiveAlert(for: snapshot)
        history = WatchGlucoseHistory.load()?.points ?? []
        stats = WatchStatsSummary.load()
    }

    /// Slots grouped into pages of 4 for the swipable grid tabs.
    var pages: [[LiveActivitySlotOption]] {
        guard !selectedSlots.isEmpty else { return [] }
        return stride(from: 0, to: selectedSlots.count, by: 4).map {
            Array(selectedSlots[$0 ..< min($0 + 4, selectedSlots.count)])
        }
    }

    func isSelected(_ option: LiveActivitySlotOption) -> Bool {
        selectedSlots.contains(option)
    }

    func toggleSlot(_ option: LiveActivitySlotOption) {
        if let idx = selectedSlots.firstIndex(of: option) {
            selectedSlots.remove(at: idx)
        } else {
            selectedSlots.append(option)
        }
        LAAppGroupSettings.setWatchSelectedSlots(selectedSlots)
    }
}

// MARK: - Page 1: Glucose

struct GlucoseView: View {
    @ObservedObject var model: WatchViewModel

    fileprivate static let staleThreshold: TimeInterval = 15 * 60

    var body: some View {
        Group {
            if let s = model.snapshot, s.age < GlucoseView.staleThreshold {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(WatchFormat.glucose(s)) \(WatchFormat.trendArrow(s))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundColor(GlucoseColor.color(forMgdl: s.glucose))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Delta: \(WatchFormat.delta(s)) \(s.unit.displayName)")
                            .font(.system(size: 14))
                            .foregroundColor(.white)

                        if s.projected != nil {
                            Text("Projected: \(WatchFormat.projected(s)) \(s.unit.displayName)")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }

                        Text("Last update: \(WatchFormat.updateTime(s))")
                            .font(.system(size: 14))
                            .foregroundColor(.white)

                        if s.isNotLooping {
                            Text("⚠ Loop inactive")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .padding(.horizontal, 4)
            } else {
                VStack(spacing: 4) {
                    Text("--")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                    Text(model.snapshot == nil ? "No data" : "Stale")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !model.isSnoozed, model.hasActiveAlert {
                SnoozeBand {
                    model.pendingSnoozeType = nil
                    model.showSnoozeSheet = true
                }
            }
        }
        .sheet(isPresented: $model.showSnoozeSheet, onDismiss: { model.refresh() }) {
            SnoozeView(isPresented: $model.showSnoozeSheet, alertType: model.pendingSnoozeType)
        }
    }
}

// MARK: - Snooze band and status

/// A slim full-width strip along the bottom of the glucose page that opens the snooze sheet.
struct SnoozeBand: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Snooze")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(Color.orange.opacity(0.2))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel("Snooze alerts")
    }
}

/// Shows how long alerts are snoozed for and lets the user cancel it.
struct SnoozeStatusView: View {
    @ObservedObject var model: WatchViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 10) {
            if let until = model.snoozeUntil {
                Text("Snoozed until \(until, style: .time)")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
            }

            Button("Cancel Snooze") {
                WatchAlertManager.shared.cancelSnooze(type: nil)
                model.refresh()
                isPresented = false
            }
            .foregroundColor(.orange)
        }
    }
}

// MARK: - Data grid page (2×2, up to 4 slots)

struct DataGridPage: View {
    let slots: [LiveActivitySlotOption]
    let snapshot: GlucoseSnapshot?

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            ForEach(0 ..< 4, id: \.self) { i in
                if i < slots.count {
                    let option = slots[i]
                    MetricCell(
                        label: option.gridLabel,
                        value: snapshot.map { WatchFormat.slotValue(option: option, snapshot: $0) } ?? "—"
                    )
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Metric cell

struct MetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(8)
    }
}

// MARK: - Settings > Visuals: slot selection checklist

struct SlotSelectionView: View {
    @ObservedObject var model: WatchViewModel

    private var displayedOptions: [LiveActivitySlotOption] {
        LiveActivitySlotOption.allCases.filter { $0 != .none && $0 != .delta && $0 != .projectedBG }
    }

    var body: some View {
        List {
            ForEach(displayedOptions, id: \.self) { option in
                Button(action: { model.toggleSlot(option) }) {
                    HStack {
                        Text(option.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(
                            systemName: model.isSelected(option)
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .foregroundColor(model.isSelected(option) ? .green : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Visuals")
    }
}
