// LoopFollow
// CrownConfirmView.swift

import SwiftUI
import WatchKit

/// Confirms a command with a deliberate Digital Crown turn, so a stray tap cannot
/// send it. The ring fills as the crown turns; it springs back after a pause.
struct CrownConfirmView: View {
    let title: String
    let detail: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var progress = 0.0
    @State private var confirmed = false
    @State private var lastTurn = Date()
    @FocusState private var crownFocused: Bool

    /// Seconds of inactivity before an unfinished turn resets.
    private static let resetAfter: TimeInterval = 2

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(confirmed ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: confirmed ? "checkmark" : "digitalcrown.arrow.clockwise")
                    .font(.title3)
                    .foregroundStyle(confirmed ? .green : .primary)
            }
            .frame(width: 70, height: 70)

            Text(confirmed ? "Confirmed" : detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .focusable()
        .focused($crownFocused)
        .onAppear { crownFocused = true }
        .digitalCrownRotation(
            $progress,
            from: 0,
            through: 1,
            by: 0.02,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: progress) { _, value in
            guard !confirmed else { return }
            lastTurn = Date()
            if value >= 1 {
                confirmed = true
                WKInterfaceDevice.current().play(.success)
                dismiss()
                onConfirm()
            } else {
                scheduleReset()
            }
        }
    }

    private func scheduleReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resetAfter) {
            guard !confirmed, Date().timeIntervalSince(lastTurn) >= Self.resetAfter else { return }
            withAnimation { progress = 0 }
        }
    }
}
