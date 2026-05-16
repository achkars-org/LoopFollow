// LoopFollow
// DiagnosticsView.swift

import Combine
import SwiftUI

struct DiagnosticsView: View {
    @State private var stats: [ChannelDiagnosticsStore.ChannelStats] = []
    @State private var totalHour = 0
    @State private var totalDay = 0

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Complication Reloads")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                ForEach(stats, id: \.channel.rawValue) { stat in
                    ChannelRow(stat: stat)
                }

                TotalRow(hourCount: totalHour, dayCount: totalDay)

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
        .onReceive(refreshTimer) { _ in loadStats() }
    }

    private func loadStats() {
        stats = ChannelDiagnosticsStore.shared.allStats()
        totalHour = ComplicationRefreshCounter.shared.hourCount
        totalDay = ComplicationRefreshCounter.shared.dayCount
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

private struct TotalRow: View {
    let hourCount: Int
    let dayCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Total")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            HStack {
                Text("all channels")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(hourCount)/hr")
                    .font(.system(size: 12))
                    .foregroundColor(hourCount > 0 ? .green : .secondary)

                Text("\(dayCount)/day")
                    .font(.system(size: 12))
                    .foregroundColor(dayCount > 0 ? .green : .secondary)
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.15))
        .cornerRadius(8)
    }
}
