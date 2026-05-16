// LoopFollow
// DiagnosticsView.swift

import SwiftUI

struct DiagnosticsView: View {
    @State private var stats: [ChannelDiagnosticsStore.ChannelStats] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Channels")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                ForEach(stats, id: \.channel.rawValue) { stat in
                    ChannelRow(stat: stat)
                }

                Button("Reset") {
                    ChannelDiagnosticsStore.shared.reset()
                    ComplicationRefreshCounter.shared.resetCounter()
                    loadStats()
                }
                .font(.system(size: 13))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .onAppear { loadStats() }
    }

    private func loadStats() {
        stats = ChannelDiagnosticsStore.shared.allStats()
    }
}

private struct ChannelRow: View {
    let stat: ChannelDiagnosticsStore.ChannelStats

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stat.channel.displayName)
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 6) {
                Group {
                    if let fired = stat.lastFired {
                        Text(fired, style: .time)
                    } else {
                        Text("never")
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)

                Spacer()

                Text("\(stat.hourCount)/hr")
                    .font(.system(size: 12))
                    .foregroundColor(stat.hourCount > 0 ? .green : .secondary)

                Text("\(stat.dayCount)/day")
                    .font(.system(size: 12))
                    .foregroundColor(stat.dayCount > 0 ? .green : .secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(8)
    }
}
