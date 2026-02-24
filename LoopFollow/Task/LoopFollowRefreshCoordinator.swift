// LoopFollowRefreshCoordinator.swift
import Foundation

actor LoopFollowRefreshCoordinator {
    static let shared = LoopFollowRefreshCoordinator()

    private var inFlight: Task<Bool, Never>?
    private var lastFinishAt: Date = .distantPast

    // Optional: coalesce storms (e.g., back-to-back silent pushes)
    private let minGap: TimeInterval = 1.0 // seconds

    func requestRefresh(
        start: @escaping () async -> Bool
    ) async -> Bool {
        // If something is already running, just await it
        if let inFlight { return await inFlight.value }

        // If we *just* finished, optionally reuse result to avoid thrash
        if Date().timeIntervalSince(lastFinishAt) < minGap {
            return true
        }

        let task = Task<Bool, Never> {
            let ok = await start()
            await self.finish(ok: ok)
            return ok
        }

        inFlight = task
        return await task.value
    }

    private func finish(ok: Bool) {
        inFlight = nil
        lastFinishAt = Date()
    }
}