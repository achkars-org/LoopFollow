// LoopFollow
// InsulinVariabilityView.swift

import SwiftUI

struct InsulinVariabilityView: View {
    @ObservedObject var viewModel: InsulinVariabilityViewModel

    private var average: InsulinVariabilityDataPoint? {
        viewModel.data.first { $0.period == .average }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insulin Variability")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let average {
                    Text(String(format: "%+.1f%% vs plan", average.variability))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let average, average.planned > 0 {
                InsulinVariabilityGraphView(data: viewModel.data)
                    .frame(height: 250)
                    .allowsHitTesting(false)
                    .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Delivered vs planned insulin. The plan is scheduled basal and carbs ÷ carb ratio, both scaled by any override.")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    InsulinVariabilityLegendItem(
                        color: InsulinVariabilityGraphView.Component.basal.color,
                        label: InsulinVariabilityGraphView.Component.basal.rawValue,
                        percentage: average.basalDeviation,
                        delivered: average.deliveredBasal,
                        planned: average.plannedBasal
                    )
                    InsulinVariabilityLegendItem(
                        color: InsulinVariabilityGraphView.Component.meal.color,
                        label: InsulinVariabilityGraphView.Component.meal.rawValue,
                        percentage: average.mealDeviation,
                        delivered: average.mealBolus,
                        planned: average.plannedMealBolus
                    )
                }
                .font(.caption2)
            } else {
                Text("No insulin data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 250)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct InsulinVariabilityLegendItem: View {
    let color: Color
    let label: String
    let percentage: Double
    let delivered: Double
    let planned: Double

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(color)
                .frame(width: 16, height: 16)
            Text(String(format: "%+.1f%%", percentage))
                .foregroundColor(.primary)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.1f of %.1f U", delivered, planned))
                .foregroundColor(.secondary)
        }
    }
}
