// LoopFollow
// PredictionDeltaView.swift

import Charts
import SwiftUI

struct PredictionDeltaView: View {
    @ObservedObject var viewModel: PredictionDeltaViewModel

    var body: some View {
        if !viewModel.deltaData.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("30-min Prediction Error (Actual − Predicted, \(Storage.shared.units.value))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                PredictionDeltaGraphView(deltaData: viewModel.deltaData)
                    .frame(height: 200)
                    .allowsHitTesting(false)
                    .clipped()

                HStack(spacing: 16) {
                    LegendItem(color: .gray.opacity(0.6), label: "5th–95th")
                    LegendItem(color: Color(UIColor.systemTeal).opacity(0.7), label: "25th–75th")
                    LegendItem(color: Color(UIColor.systemTeal), label: "Median")
                }
                .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct PredictionDeltaGraphView: UIViewRepresentable {
    let deltaData: [PredictionDeltaDataPoint]

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        var chartView: LineChartView?
        var boundsObservation: NSKeyValueObservation?

        func observeFirstLayout(then action: @escaping () -> Void) {
            guard let chart = chartView else { return }
            boundsObservation = chart.observe(\.bounds, options: .new) { [weak self] view, _ in
                guard view.bounds.height > 0 else { return }
                self?.boundsObservation = nil
                action()
            }
        }
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = NonInteractiveContainerView()
        containerView.backgroundColor = .systemBackground

        let chartView = LineChartView()
        chartView.rightAxis.enabled = true
        chartView.leftAxis.enabled = false
        chartView.xAxis.labelPosition = .bottom
        chartView.rightAxis.drawGridLinesEnabled = false
        chartView.leftAxis.drawGridLinesEnabled = false
        chartView.xAxis.drawGridLinesEnabled = false
        chartView.legend.enabled = false
        chartView.chartDescription.enabled = false
        chartView.isUserInteractionEnabled = false

        containerView.addSubview(chartView)
        chartView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chartView.topAnchor.constraint(equalTo: containerView.topAnchor),
            chartView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            chartView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            chartView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        context.coordinator.chartView = chartView
        return containerView
    }

    func updateUIView(_ containerView: UIView, context: Context) {
        guard let chartView = context.coordinator.chartView,
              !deltaData.isEmpty
        else { return }

        if chartView.bounds.height == 0 {
            context.coordinator.observeFirstLayout { renderChart(chartView) }
            return
        }

        renderChart(chartView)
    }

    private func renderChart(_ chartView: LineChartView) {
        let isMgDL = Storage.shared.units.value == "mg/dL"
        let maxY: Double = isMgDL ? 27.0 : 1.5
        let minY = -maxY

        let clamp: (Double) -> Double = { min(max($0, minY), maxY) }

        var p5Entries: [ChartDataEntry] = []
        var p25Entries: [ChartDataEntry] = []
        var p50Entries: [ChartDataEntry] = []
        var p75Entries: [ChartDataEntry] = []
        var p95Entries: [ChartDataEntry] = []

        for point in deltaData {
            let x = Double(point.timeOfDay) / 60.0
            p5Entries.append(ChartDataEntry(x: x, y: clamp(point.p5)))
            p25Entries.append(ChartDataEntry(x: x, y: clamp(point.p25)))
            p50Entries.append(ChartDataEntry(x: x, y: clamp(point.p50)))
            p75Entries.append(ChartDataEntry(x: x, y: clamp(point.p75)))
            p95Entries.append(ChartDataEntry(x: x, y: clamp(point.p95)))
        }

        let sortedP5 = p5Entries.sorted { $0.x < $1.x }
        let sortedP25 = p25Entries.sorted { $0.x < $1.x }
        let sortedP50 = p50Entries.sorted { $0.x < $1.x }
        let sortedP75 = p75Entries.sorted { $0.x < $1.x }
        let sortedP95 = p95Entries.sorted { $0.x < $1.x }

        guard !sortedP50.isEmpty else { return }

        let p5DataSet = makeLineDataSet(entries: sortedP5, color: NSUIColor.systemGray.withAlphaComponent(0.6), width: 1.5)
        let p25DataSet = makeLineDataSet(entries: sortedP25, color: NSUIColor.systemTeal.withAlphaComponent(0.7), width: 1.5)
        let p50DataSet = makeLineDataSet(entries: sortedP50, color: NSUIColor.systemTeal, width: 2.5)
        let p75DataSet = makeLineDataSet(entries: sortedP75, color: NSUIColor.systemTeal.withAlphaComponent(0.7), width: 1.5)
        let p95DataSet = makeLineDataSet(entries: sortedP95, color: NSUIColor.systemGray.withAlphaComponent(0.6), width: 1.5)

        var hourLines: [ChartDataEntry] = []
        for hour in 0 ... 24 {
            let x = Double(hour)
            hourLines.append(ChartDataEntry(x: x, y: minY))
            hourLines.append(ChartDataEntry(x: x, y: maxY))
            if hour < 24 {
                hourLines.append(ChartDataEntry(x: x + 0.0001, y: minY))
            }
        }
        let hourLinesDataSet = LineChartDataSet(entries: hourLines, label: "")
        hourLinesDataSet.colors = [NSUIColor.label.withAlphaComponent(0.3)]
        hourLinesDataSet.lineWidth = 1
        hourLinesDataSet.drawCirclesEnabled = false
        hourLinesDataSet.drawValuesEnabled = false

        chartView.rightAxis.axisMinimum = minY
        chartView.rightAxis.axisMaximum = maxY

        let zeroLine = ChartLimitLine(limit: 0)
        zeroLine.lineColor = NSUIColor.systemRed.withAlphaComponent(0.7)
        zeroLine.lineWidth = 1.5
        zeroLine.lineDashLengths = [6.0, 4.0]
        chartView.rightAxis.removeAllLimitLines()
        chartView.rightAxis.addLimitLine(zeroLine)

        chartView.rightAxis.valueFormatter = DeltaYAxisFormatter()

        let data = LineChartData()
        data.append(p5DataSet)
        data.append(p25DataSet)
        data.append(p50DataSet)
        data.append(p75DataSet)
        data.append(p95DataSet)
        data.append(hourLinesDataSet)

        chartView.data = data
        chartView.notifyDataSetChanged()
        chartView.setNeedsDisplay()
    }

    private func makeLineDataSet(entries: [ChartDataEntry], color: NSUIColor, width: CGFloat) -> LineChartDataSet {
        let dataSet = LineChartDataSet(entries: entries, label: "")
        dataSet.colors = [color]
        dataSet.lineWidth = width
        dataSet.drawCirclesEnabled = false
        dataSet.drawValuesEnabled = false
        dataSet.drawFilledEnabled = false
        dataSet.mode = .linear
        return dataSet
    }
}

private class DeltaYAxisFormatter: NSObject, AxisValueFormatter {
    func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        let isMgDL = Storage.shared.units.value == "mg/dL"
        let fmt = isMgDL ? "%.0f" : "%.1f"
        if value == 0 { return "0" }
        return String(format: value > 0 ? "+\(fmt)" : fmt, value)
    }
}
