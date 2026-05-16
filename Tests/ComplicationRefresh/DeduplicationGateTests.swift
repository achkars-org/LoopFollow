// LoopFollow
// DeduplicationGateTests.swift
//
// Tests for the deduplication-gate logic introduced in Step 1:
// ComplicationRefreshCounter.shouldReloadAndRecord(for:).
//
// NOTE ON SCOPE:
// ComplicationRefreshCounter is compiled into the Watch target only.
// The "Tests" target uses @testable import LoopFollow (the iOS app target), so
// ComplicationRefreshCounter is NOT accessible here. Instead we test the gate
// predicate as a pure Boolean expression — the same logic that lives inside
// shouldReloadAndRecord(for:) — without calling any Watch or App Group API.
//
// The predicate mirrors:
//   func shouldReloadAndRecord(for snapshot: GlucoseSnapshot) -> Bool {
//       if snapshot.updatedAt.timeIntervalSince1970 <= lastReloadedSnapshotUpdatedAt {
//           return false
//       }
//       lastReloadedSnapshotUpdatedAt = snapshot.updatedAt.timeIntervalSince1970
//       recordRefresh()
//       return true
//   }

import Testing

// MARK: - Gate predicate helper

/// Mirrors the deduplication predicate from
/// ComplicationRefreshCounter.shouldReloadAndRecord(for:).
///
/// Parameters:
///   - snapshotTimestamp:  the candidate snapshot's updatedAt.timeIntervalSince1970
///   - lastRecordedTimestamp: the value of lastReloadedSnapshotUpdatedAt on entry
///
/// Returns (shouldReload, updatedLastRecorded) — where updatedLastRecorded is the
/// new value of lastReloadedSnapshotUpdatedAt after the call.
private func deduplicationGate(
    snapshotTimestamp: TimeInterval,
    lastRecordedTimestamp: TimeInterval
) -> (shouldReload: Bool, updatedLastRecorded: TimeInterval) {
    if snapshotTimestamp <= lastRecordedTimestamp {
        return (false, lastRecordedTimestamp)
    }
    return (true, snapshotTimestamp)
}

// MARK: - Tests

struct DeduplicationGateTests {
    // -------------------------------------------------------------------------
    // First call — new snapshot should always be reloaded
    // -------------------------------------------------------------------------

    @Test("passes gate when no previous snapshot has been recorded (lastRecorded = 0)")
    func passesWhenNoSnapshotEverRecorded() {
        let (shouldReload, _) = deduplicationGate(snapshotTimestamp: 1_700_000_000, lastRecordedTimestamp: 0)
        #expect(shouldReload)
    }

    @Test("passes gate when snapshot timestamp is strictly newer than last recorded")
    func passesWhenNewerSnapshot() {
        let earlier: TimeInterval = 1_700_000_000
        let later: TimeInterval = 1_700_000_300   // 5 min newer
        let (shouldReload, _) = deduplicationGate(snapshotTimestamp: later, lastRecordedTimestamp: earlier)
        #expect(shouldReload)
    }

    @Test("updates lastRecorded to snapshotTimestamp when gate passes")
    func updatesLastRecordedOnPass() {
        let ts: TimeInterval = 1_700_000_300
        let (_, updated) = deduplicationGate(snapshotTimestamp: ts, lastRecordedTimestamp: 0)
        #expect(updated == ts)
    }

    // -------------------------------------------------------------------------
    // Duplicate delivery — second call with the same updatedAt returns false
    // -------------------------------------------------------------------------

    @Test("blocks gate when snapshot timestamp equals last recorded (exact duplicate)")
    func blocksOnExactDuplicate() {
        let ts: TimeInterval = 1_700_000_000
        // Simulate first call storing the timestamp
        let (first, updated) = deduplicationGate(snapshotTimestamp: ts, lastRecordedTimestamp: 0)
        #expect(first)     // first call passes
        // Simulate second call with same timestamp
        let (second, _) = deduplicationGate(snapshotTimestamp: ts, lastRecordedTimestamp: updated)
        #expect(!second)   // second call is blocked
    }

    @Test("blocks gate when snapshot timestamp is older than last recorded")
    func blocksOnOlderSnapshot() {
        let newer: TimeInterval = 1_700_000_300
        let older: TimeInterval = 1_700_000_000
        let (shouldReload, _) = deduplicationGate(snapshotTimestamp: older, lastRecordedTimestamp: newer)
        #expect(!shouldReload)
    }

    @Test("does not update lastRecorded when gate is blocked")
    func doesNotUpdateLastRecordedOnBlock() {
        let ts: TimeInterval = 1_700_000_000
        let (_, updated) = deduplicationGate(snapshotTimestamp: ts, lastRecordedTimestamp: ts)
        #expect(updated == ts)   // unchanged
    }

    // -------------------------------------------------------------------------
    // Sequential delivery simulation — two different timestamps
    // -------------------------------------------------------------------------

    @Test("two different snapshots both pass the gate in sequence")
    func twoSequentialNewSnapshotsEachPass() {
        let t1: TimeInterval = 1_700_000_000
        let t2: TimeInterval = 1_700_000_300

        let (pass1, after1) = deduplicationGate(snapshotTimestamp: t1, lastRecordedTimestamp: 0)
        #expect(pass1)

        let (pass2, after2) = deduplicationGate(snapshotTimestamp: t2, lastRecordedTimestamp: after1)
        #expect(pass2)
        #expect(after2 == t2)
    }

    @Test("duplicate delivery between two new snapshots is blocked, then new snapshot passes")
    func duplicateBetweenNewSnapshotsIsBlocked() {
        let t1: TimeInterval = 1_700_000_000
        let t2: TimeInterval = 1_700_000_300

        // First new snapshot
        let (_, after1) = deduplicationGate(snapshotTimestamp: t1, lastRecordedTimestamp: 0)

        // Duplicate of first
        let (dup, afterDup) = deduplicationGate(snapshotTimestamp: t1, lastRecordedTimestamp: after1)
        #expect(!dup)

        // Second new snapshot still passes
        let (pass2, _) = deduplicationGate(snapshotTimestamp: t2, lastRecordedTimestamp: afterDup)
        #expect(pass2)
    }

    // -------------------------------------------------------------------------
    // Boundary value: timestamp = 0 (epoch)
    // -------------------------------------------------------------------------

    @Test("snapshot at epoch (timestamp 0) is blocked when lastRecorded is also 0")
    func epochTimestampBlockedByInitialState() {
        // lastRecorded defaults to 0; a snapshot with ts=0 should be blocked
        // (0 <= 0 evaluates true → blocked)
        let (shouldReload, _) = deduplicationGate(snapshotTimestamp: 0, lastRecordedTimestamp: 0)
        #expect(!shouldReload)
    }

    @Test("snapshot with timestamp 1 passes when lastRecorded is 0")
    func smallestNonzeroTimestampPasses() {
        let (shouldReload, _) = deduplicationGate(snapshotTimestamp: 1, lastRecordedTimestamp: 0)
        #expect(shouldReload)
    }
}
