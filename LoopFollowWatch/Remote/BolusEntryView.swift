// LoopFollow
// BolusEntryView.swift

import SwiftUI
import WatchKit

/// The AID's recommendation and the phone's Quick-Pick boluses, opened from the
/// amount screen. Every choice still needs the crown confirmation.
struct BolusPresetsView: View {
    let remote: WatchRemoteConfig

    @EnvironmentObject private var navigator: WatchNavigator
    @State private var staleRecommendation: Double?

    /// Same cut-offs as the phone's bolus screens.
    private static let recommendationMaxAge: TimeInterval = 12 * 60
    static let recommendationWarnAge: TimeInterval = 5 * 60

    static func quickPicks(_ remote: WatchRemoteConfig) -> [Double] {
        remote.quickPickBoluses.filter { $0 > 0 && $0 <= remote.maxBolus }
    }

    /// A recommendation recent enough to offer, rounded down to the watch's step.
    static func freshRecommendation(_ remote: WatchRemoteConfig) -> (units: Double, age: TimeInterval)? {
        guard let rec = remote.recommendedBolus, rec > 0, let at = remote.recommendedBolusAt else { return nil }
        let age = Date().timeIntervalSince(at)
        let stepped = BolusAmountView.roundedDown(min(rec, remote.maxBolus), step: BolusAmountView.step(remote))
        guard age < recommendationMaxAge, stepped > 0 else { return nil }
        return (stepped, age)
    }

    static func hasPresets(_ remote: WatchRemoteConfig) -> Bool {
        freshRecommendation(remote) != nil || !quickPicks(remote).isEmpty
    }

    var body: some View {
        List {
            recommendation
            ForEach(Self.quickPicks(remote), id: \.self) { units in
                Button {
                    confirm(units)
                } label: {
                    Text("\(WatchFormat.insulin(units)) U")
                }
            }
        }
        .navigationTitle("Presets")
        .alert(
            "Old Calculation Warning",
            isPresented: Binding(get: { staleRecommendation != nil }, set: { if !$0 { staleRecommendation = nil } })
        ) {
            Button("Use Anyway") {
                if let staleRecommendation { confirm(staleRecommendation) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recommended bolus was calculated more than 5 minutes ago. New treatments may have occurred since then. Proceed with caution.")
        }
    }

    @ViewBuilder
    private var recommendation: some View {
        if let rec = Self.freshRecommendation(remote) {
            Section {
                Button {
                    if rec.age >= Self.recommendationWarnAge {
                        staleRecommendation = rec.units
                    } else {
                        confirm(rec.units)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recommended \(WatchFormat.insulin(rec.units)) U")
                        Text("Calculated \(Int(rec.age / 60)) min ago")
                            .font(.caption2)
                            .foregroundStyle(rec.age >= Self.recommendationWarnAge ? .red : .secondary)
                    }
                }
            }
        }
    }

    private func confirm(_ units: Double) {
        navigator.push(.confirm(BolusAmountView.request(units)))
    }
}

/// Any amount, set with the Digital Crown or − and +, starting at the AID's
/// recommendation while it is under 5 minutes old; presets one tap away when
/// the phone has any.
struct BolusAmountView: View {
    let remote: WatchRemoteConfig

    @EnvironmentObject private var navigator: WatchNavigator
    @State private var units = 0.0
    /// Seeded once, so coming back from the confirmation keeps the user's amount.
    @State private var seeded = false
    @State private var seededRecommendation: (units: Double, age: TimeInterval)?
    @FocusState private var amountFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                AmountField(value: $units, unit: "U", step: Self.step(remote), crownSensitivity: .low, maximum: remote.maxBolus, isHighlighted: amountFocused, format: WatchFormat.insulin)
                    .focused($amountFocused)
                if let rec = seededRecommendation {
                    Text("Recommended \(WatchFormat.insulin(rec.units)) U, \(Int(rec.age / 60)) min ago")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Text("Max \(WatchFormat.insulin(remote.maxBolus)) U")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Continue") {
                    navigator.push(.confirm(Self.request(units)))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(units <= 0)
                if BolusPresetsView.hasPresets(remote) {
                    Button("Presets") {
                        navigator.push(.bolusPresets)
                    }
                }
            }
        }
        .navigationTitle("Bolus")
        .onAppear {
            amountFocused = true
            guard !seeded else { return }
            seeded = true
            if let rec = BolusPresetsView.freshRecommendation(remote), rec.age < BolusPresetsView.recommendationWarnAge {
                units = rec.units
                seededRecommendation = rec
            }
        }
    }

    /// 0.05 U, or the pump's increment when it is coarser: finer steps are too
    /// hard to land on with the crown.
    static func step(_ remote: WatchRemoteConfig) -> Double {
        max(remote.bolusIncrement, 0.05)
    }

    static func request(_ units: Double) -> CommandRequest {
        CommandRequest(title: "Bolus", lines: ["\(WatchFormat.insulin(units)) U"], action: .bolus(units: units), deliversInsulin: true)
    }

    static func roundedDown(_ value: Double, step: Double) -> Double {
        let stepped = ((value / step) + 1e-10).rounded(.down) * step
        return (stepped * 1000).rounded() / 1000
    }
}

/// A value edited with the Digital Crown or the − and + buttons, in fixed steps
/// between a minimum and a maximum.
struct AmountField: View {
    @Binding var value: Double
    let unit: String
    let step: Double
    var crownSensitivity: DigitalCrownRotationalSensitivity = .medium
    var minimum: Double = 0
    let maximum: Double
    /// The caller owns focus; this only draws the highlight.
    let isHighlighted: Bool
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus", by: -step)
                .disabled(value <= minimum)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(format(value))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            stepButton("plus", by: step)
                .disabled(value >= maximum)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).stroke(isHighlighted ? Color.green : Color.gray.opacity(0.4), lineWidth: 1.5))
        .focusable()
        .digitalCrownRotation($value, from: minimum, through: max(maximum, minimum + step), by: step, sensitivity: crownSensitivity, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: value) { _, newValue in
            let clamped = stepped(newValue)
            if clamped != newValue { value = clamped }
        }
    }

    private func stepButton(_ symbol: String, by delta: Double) -> some View {
        Button {
            value = stepped(value + delta)
            WKInterfaceDevice.current().play(.click)
        } label: {
            Image(systemName: "\(symbol).circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.green)
    }

    /// Nearest step, kept between the minimum and the maximum.
    private func stepped(_ newValue: Double) -> Double {
        let nearest = ((newValue / step).rounded() * step * 1000).rounded() / 1000
        return min(max(minimum, nearest), maximum)
    }
}
