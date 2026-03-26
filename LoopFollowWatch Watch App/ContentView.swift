//
//  ContentView.swift
//  LoopFollowWatch Watch App
//
//  Created by Philippe Achkar on 2026-03-10.
//  Copyright © 2026 Jon Fawcett. All rights reserved.
//

import Combine
import SwiftUI
import WatchConnectivity

// MARK: - Root view

struct ContentView: View {
    @StateObject private var model = WatchViewModel()

    var body: some View {
        TabView {
            GlucoseView(model: model)

            ForEach(Array(model.pages.enumerated()), id: \.offset) { _, page in
                DataGridPage(slots: page, snapshot: model.snapshot)
            }

            SlotSelectionView(model: model)
        }
        .tabViewStyle(.page)
        .onAppear { model.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: WatchSessionReceiver.snapshotReceivedNotification
            )
        ) { notification in
            if let s = notification.userInfo?["snapshot"] as? GlucoseSnapshot {
                model.update(snapshot: s)
            } else {
                model.refresh()
            }
        }
    }
}

// MARK: - View model

final class WatchViewModel: ObservableObject {
    @Published var snapshot: GlucoseSnapshot?
    @Published var selectedSlots: [LiveActivitySlotOption] = LAAppGroupSettings.watchSelectedSlots()

    private var timer: Timer?

    init() {
        snapshot = GlucoseSnapshotStore.shared.load()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        if let loaded = GlucoseSnapshotStore.shared.load() {
            snapshot = loaded
        }
        selectedSlots = LAAppGroupSettings.watchSelectedSlots()
    }

    func update(snapshot: GlucoseSnapshot) {
        self.snapshot = snapshot
        selectedSlots = LAAppGroupSettings.watchSelectedSlots()
    }

    /// Slots grouped into pages of 4 for the swipable grid tabs.
    var pages: [[LiveActivitySlotOption]] {
        guard !selectedSlots.isEmpty else { return [] }
        return stride(from: 0, to: selectedSlots.count, by: 4).map {
            Array(selectedSlots[$0..<min($0 + 4, selectedSlots.count)])
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
                    if s.projected != nil {
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
                Text(model.snapshot == nil ? "No data" : "Stale")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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
            ForEach(0..<4, id: \.self) { i in
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

// MARK: - Last tab: slot selection checklist

struct SlotSelectionView: View {
    @ObservedObject var model: WatchViewModel

    var body: some View {
        List {
            ForEach(LiveActivitySlotOption.allCases.filter { $0 != .none }, id: \.self) { option in
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
        .navigationTitle("Data")
    }
}

// MARK: - UIColor → SwiftUI Color bridge

private extension UIColor {
    var swiftUIColor: Color { Color(self) }
}
