// LoopFollow
// PredictionDeltaViewModel.swift

import Combine
import Foundation

class PredictionDeltaViewModel: ObservableObject {
    @Published var deltaData: [PredictionDeltaDataPoint] = []

    private let dataService: StatsDataService

    init(dataService: StatsDataService) {
        self.dataService = dataService
    }

    func calculateDelta() {
        let bgData = dataService.getBGData()
        let snapshots = dataService.getStatsPredictionSnapshots()
        let carbData = dataService.getCarbData()
        let bolusData = dataService.getBolusData()
        deltaData = PredictionDeltaCalculator.calculate(bgData: bgData, snapshots: snapshots, carbData: carbData, bolusData: bolusData)
    }

    func clearStats() {
        deltaData = []
    }
}
