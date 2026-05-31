// LoopFollow
// StalenessGuardTests.swift
//
// Tests for the staleness-guard logic introduced in handleRefresh()'s else-branch.
//
// NOTE ON SCOPE:
// ComplicationRefreshCounter is compiled into the "LoopFollowWatch Watch App" target only.
// The "Tests" target uses @testable import LoopFollow (the iOS app target), so
// ComplicationRefreshCounter is NOT accessible here.  Instead we test the guard
// predicate as a pure Boolean expression — the same logic that lives inside
// handleRefresh() — without calling any Watch or App Group API.

import Testing

// MARK: - Guard predicate helper

/// Mirrors the staleness-guard condition from WatchAppDelegate.handleRefresh():
///
///   if snapshotAge >= stalenessCutoff,
///      timeSinceLastRefresh >= reloadCooldown { ... }
///
/// Both thresholds are defined in LoopFollowWatchApp.swift as named constants:
///   let stalenessCutoff: TimeInterval = 360
///   let reloadCooldown:  TimeInterval = 300
private func shouldReload(snapshotAge: TimeInterval, timeSinceLastRefresh: TimeInterval) -> Bool {
    let stalenessCutoff: TimeInterval = 360
    let reloadCooldown: TimeInterval = 300
    return snapshotAge >= stalenessCutoff && timeSinceLastRefresh >= reloadCooldown
}

// MARK: - Tests

struct StalenessGuardTests {
    // -------------------------------------------------------------------------
    // Reload IS triggered
    // -------------------------------------------------------------------------

    @Test("triggers reload when snapshot is stale and cooldown has elapsed")
    func triggersWhenBothConditionsMet() {
        // snapshotAge = 360 s (exactly at threshold), timeSinceLastRefresh = 300 s (exactly at cooldown)
        #expect(shouldReload(snapshotAge: 360, timeSinceLastRefresh: 300))
    }

    @Test("triggers reload when snapshot age and time-since-refresh both exceed thresholds")
    func triggersWhenBothExceedThresholds() {
        #expect(shouldReload(snapshotAge: 600, timeSinceLastRefresh: 500))
    }

    @Test("triggers reload when snapshot age is infinite (no stored snapshot)")
    func triggersWhenNoStoredSnapshot() {
        // GlucoseSnapshotStore.shared.load() returns nil  →  age is .infinity
        #expect(shouldReload(snapshotAge: .infinity, timeSinceLastRefresh: 300))
    }

    @Test("triggers reload when time-since-refresh is infinite (no refresh ever recorded)")
    func triggersWhenNoRefreshEverRecorded() {
        // ComplicationRefreshCounter.timeSinceLastRefresh returns .infinity when storedTimestamps is empty
        #expect(shouldReload(snapshotAge: 360, timeSinceLastRefresh: .infinity))
    }

    @Test("triggers reload when both values are infinite")
    func triggersWhenBothInfinite() {
        #expect(shouldReload(snapshotAge: .infinity, timeSinceLastRefresh: .infinity))
    }

    // -------------------------------------------------------------------------
    // Reload is NOT triggered
    // -------------------------------------------------------------------------

    @Test("suppresses reload when snapshot is fresh (age below threshold)")
    func suppressesWhenSnapshotFresh() {
        // snapshotAge = 359 s (just below stalenessCutoff of 360 s)
        #expect(!shouldReload(snapshotAge: 359, timeSinceLastRefresh: 300))
    }

    @Test("suppresses reload when cooldown has not elapsed")
    func suppressesWhenCooldownActive() {
        // timeSinceLastRefresh = 299 s (just below reloadCooldown of 300 s)
        #expect(!shouldReload(snapshotAge: 360, timeSinceLastRefresh: 299))
    }

    @Test("suppresses reload when both conditions are below threshold")
    func suppressesWhenBothBelowThreshold() {
        #expect(!shouldReload(snapshotAge: 100, timeSinceLastRefresh: 60))
    }

    @Test("suppresses reload when snapshot is fresh regardless of cooldown expiry")
    func suppressesWhenOnlyRefreshCooldownMet() {
        #expect(!shouldReload(snapshotAge: 0, timeSinceLastRefresh: 999))
    }

    @Test("suppresses reload when only snapshot is stale but cooldown is active")
    func suppressesWhenOnlyStalenessMet() {
        #expect(!shouldReload(snapshotAge: 999, timeSinceLastRefresh: 0))
    }

    // -------------------------------------------------------------------------
    // Threshold boundary values
    // -------------------------------------------------------------------------

    @Test("stalenessCutoff boundary: 359.9 is below threshold")
    func stalenessBoundaryJustBelow() {
        #expect(!shouldReload(snapshotAge: 359.9, timeSinceLastRefresh: 300))
    }

    @Test("stalenessCutoff boundary: 360.0 is at threshold (inclusive)")
    func stalenessBoundaryAtThreshold() {
        #expect(shouldReload(snapshotAge: 360.0, timeSinceLastRefresh: 300))
    }

    @Test("reloadCooldown boundary: 299.9 is below cooldown")
    func cooldownBoundaryJustBelow() {
        #expect(!shouldReload(snapshotAge: 360, timeSinceLastRefresh: 299.9))
    }

    @Test("reloadCooldown boundary: 300.0 is at cooldown (inclusive)")
    func cooldownBoundaryAtThreshold() {
        #expect(shouldReload(snapshotAge: 360, timeSinceLastRefresh: 300.0))
    }
}
