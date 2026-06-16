// LoopFollow
// PredictionDeltaCalculator.swift

import Foundation

struct PredictionDeltaDataPoint {
    let timeOfDay: Int
    let p5: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p95: Double
}

class PredictionDeltaCalculator {
    static func calculate(
        bgData: [ShareGlucoseData],
        snapshots: [PredictionSnapshot],
        carbData: [MainViewController.carbGraphStruct] = [],
        bolusData: [MainViewController.bolusGraphStruct] = []
    ) -> [PredictionDeltaDataPoint] {
        guard !bgData.isEmpty, !snapshots.isEmpty else { return [] }

        let sortedSnaps = snapshots.sorted { $0.runTime < $1.runTime }
        var hourDeltas: [Int: [Double]] = [:]
        let calendar = dateTimeUtils.displayCalendar()

        for reading in bgData {
            let t = reading.date
            let idealSnapshotTime = t - 1800
            guard let snap = sortedSnaps.last(where: { $0.runTime <= idealSnapshotTime + 300 }),
                  snap.runTime >= idealSnapshotTime - 300,
                  let predictedMgdl = snap.predictedValue(at: t)
            else { continue }

            // Skip readings where carbs or a manual bolus were entered after the snapshot
            // was made — Loop had no knowledge of these events and the resulting divergence
            // is not algorithm bias. SMBs are excluded from bolusData (separate array).
            let snapTime = snap.runTime
            guard !carbData.contains(where: { $0.date > snapTime && $0.date <= t }),
                  !bolusData.contains(where: { $0.date > snapTime && $0.date <= t }) else { continue }

            let actualMgdl = Double(reading.sgv) // sgv is always mg/dL from Nightscout
            let delta = actualMgdl - predictedMgdl

            let date = Date(timeIntervalSince1970: t)
            let hour = calendar.dateComponents([.hour], from: date).hour ?? 0
            hourDeltas[hour, default: []].append(delta)
        }

        let convert: (Double) -> Double = { v in
            Storage.shared.units.value == "mg/dL" ? v : v * GlucoseConversion.mgDlToMmolL
        }

        return (0 ..< 24).compactMap { hour in
            guard let deltas = hourDeltas[hour], !deltas.isEmpty else { return nil }
            let sorted = deltas.sorted()
            return PredictionDeltaDataPoint(
                timeOfDay: hour * 60,
                p5: convert(PercentileCalculator.percentile(sorted, p: 0.05)),
                p25: convert(PercentileCalculator.percentile(sorted, p: 0.25)),
                p50: convert(PercentileCalculator.percentile(sorted, p: 0.50)),
                p75: convert(PercentileCalculator.percentile(sorted, p: 0.75)),
                p95: convert(PercentileCalculator.percentile(sorted, p: 0.95))
            )
        }.sorted { $0.timeOfDay < $1.timeOfDay }
    }
}
