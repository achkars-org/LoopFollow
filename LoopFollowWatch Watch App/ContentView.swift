//
//  ContentView.swift
//  LoopFollowWatch Watch App
//
//  Created by Philippe Achkar on 2026-03-10.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import SwiftUI
import WatchConnectivity

// MARK: - Root view

struct ContentView: View {
    @StateObject private var model = WatchViewModel()

    var body: some View {
        TabView {
            GlucoseView(model: model)
            DataCardView(model: model)
            SettingsView(model: model)
        }
        .tabViewStyle(.page)
        .onAppear { model.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: WatchSessionReceiver.snapshotReceivedNotification
            )
        ) { _ in
            model.refresh()
        }
    }
}

// MARK: - View model

final class WatchViewModel: ObservableObject {
    @Published var snapshot: GlucoseSnapshot?
    @Published var slots: [LiveActivitySlotOption] = LAAppGroupSettings.watchSlots()

    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        snapshot = GlucoseSnapshotStore.shared.load()
        slots = LAAppGroupSettings.watchSlots()
    }

    func saveSlots() {
        LAAppGroupSettings.setWatchSlots(slots)
    }
}

// MARK: - Page 1: Glucose

struct GlucoseView: View {
    @ObservedObject var model: WatchViewModel

    var body: some View {
        if let s = model.snapshot, s.age < 900, !s.isNotLooping {
            HStack(spacing: 8) {
                Text(WatchFormat.glucose(s))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundColor(ComplicationEntryBuilder.thresholdColor(for: s).swiftUIColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(WatchFormat.trendArrow(s))
                        .font(.system(size: 18, weight: .medium))
                    Text(WatchFormat.delta(s))
                        .font(.system(size: 14))
                    if let _ = s.projected {
                        Text(WatchFormat.projected(s))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    Text(WatchFormat.minAgo(s))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    if WCSession.default.isReachable {
                        Button("Open iPhone") {
                            WCSession.default.sendMessage(["action": "open"], replyHandler: nil)
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }
            .padding(.horizontal, 4)
        } else {
            VStack(spacing: 4) {
                Text("--")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Page 2: Data card

struct DataCardView: View {
    @ObservedObject var model: WatchViewModel

    var body: some View {
        let s = model.snapshot
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            ForEach(0..<4, id: \.self) { i in
                let option = i < model.slots.count ? model.slots[i] : .none
                MetricCell(label: option.gridLabel, value: s.map { WatchFormat.slotValue(option: option, snapshot: $0) } ?? "—")
            }
        }
        .padding(.horizontal, 4)
    }
}

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

// MARK: - Page 3: Settings

struct SettingsView: View {
    @ObservedObject var model: WatchViewModel

    private let slotLabels = ["Top Left", "Bottom Left", "Top Right", "Bottom Right"]

    var body: some View {
        List {
            ForEach(0..<4, id: \.self) { i in
                let binding = Binding(
                    get: { i < model.slots.count ? model.slots[i] : .none },
                    set: { newVal in
                        if i < model.slots.count {
                            model.slots[i] = newVal
                            model.saveSlots()
                        }
                    }
                )
                Picker(slotLabels[i], selection: binding) {
                    ForEach(LiveActivitySlotOption.allCases, id: \.self) { opt in
                        Text(opt.displayName).tag(opt)
                    }
                }
            }
        }
        .navigationTitle("Watch Settings")
    }
}

// MARK: - UIColor → SwiftUI Color bridge

private extension UIColor {
    var swiftUIColor: Color { Color(self) }
}
