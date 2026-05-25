import XCTest
@testable import NiyoraCompanion

/// Tests for `LocalSessionStore` completed-count, persistence, and reset.
///
/// `LocalSessionStore` persists to a JSON file in the app's Documents
/// directory (a single, shared location), so this test class isolates
/// itself by calling `clear()` in `setUp` and `tearDown`. Each test
/// tags its rows with a per-run UUID so cross-test bleed would surface
/// immediately as a count mismatch.
final class LocalSessionStoreTests: XCTestCase {

    private var runTag: String!

    override func setUp() {
        super.setUp()
        runTag = "test-\(UUID().uuidString)"
        LocalSessionStore.clear()
    }

    override func tearDown() {
        LocalSessionStore.clear()
        runTag = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSession(
        completed: Bool = true,
        at date: Date = Date()
    ) -> LocalSessionStore.Session {
        LocalSessionStore.Session(
            id: UUID().uuidString,
            techniqueName: runTag,
            duration: 60,
            completed: completed,
            timestamp: date
        )
    }

    private func increment(completed: Bool = true) {
        LocalSessionStore.add(session: makeSession(completed: completed))
    }

    // MARK: - Fresh-install behavior

    func test_completedCount_startsAtZeroOnFreshInstall() {
        XCTAssertEqual(LocalSessionStore.completedCount(), 0)
    }

    func test_count_startsAtZeroOnFreshInstall() {
        XCTAssertEqual(LocalSessionStore.count(), 0)
    }

    func test_all_startsEmptyOnFreshInstall() {
        XCTAssertTrue(LocalSessionStore.all().isEmpty)
    }

    // MARK: - Increment

    func test_addingOneCompletedSession_incrementsCompletedCountByOne() {
        increment()
        XCTAssertEqual(LocalSessionStore.completedCount(), 1)
    }

    func test_addingMultipleCompletedSessions_incrementsByOneEachTime() {
        for expected in 1...5 {
            increment()
            XCTAssertEqual(
                LocalSessionStore.completedCount(),
                expected,
                "completedCount mismatch after \(expected) adds"
            )
        }
    }

    func test_addingAbandonedSession_doesNotIncrementCompletedCount() {
        increment(completed: false)
        XCTAssertEqual(LocalSessionStore.completedCount(), 0)
        // But it does show up in the total count.
        XCTAssertEqual(LocalSessionStore.count(), 1)
    }

    func test_mixedCompletedAndAbandoned_completedCountOnlyCountsCompleted() {
        increment(completed: true)
        increment(completed: false)
        increment(completed: true)
        increment(completed: false)
        increment(completed: true)
        XCTAssertEqual(LocalSessionStore.completedCount(), 3)
        XCTAssertEqual(LocalSessionStore.count(), 5)
    }

    // MARK: - Persistence across reads

    func test_completedCount_persistsAcrossMultipleReads() {
        increment()
        increment()
        increment()
        // Read twice — second read should see the same value (the store
        // re-reads from disk each call, so this verifies persistence).
        XCTAssertEqual(LocalSessionStore.completedCount(), 3)
        XCTAssertEqual(LocalSessionStore.completedCount(), 3)
        XCTAssertEqual(LocalSessionStore.completedCount(), 3)
    }

    func test_addedSession_isReturnedByAll() {
        let session = makeSession()
        LocalSessionStore.add(session: session)
        let all = LocalSessionStore.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, session.id)
    }

    func test_all_isOrderedMostRecentFirst() {
        let oldest = makeSession(at: Date(timeIntervalSince1970: 1_000))
        let middle = makeSession(at: Date(timeIntervalSince1970: 2_000))
        let newest = makeSession(at: Date(timeIntervalSince1970: 3_000))
        // Add out of chronological order to prove sorting.
        LocalSessionStore.add(session: middle)
        LocalSessionStore.add(session: oldest)
        LocalSessionStore.add(session: newest)

        let ordered = LocalSessionStore.all().map(\.id)
        XCTAssertEqual(ordered, [newest.id, middle.id, oldest.id])
    }

    // MARK: - Idempotent add (same id)

    func test_addingSameIdTwice_doesNotDoubleCount() {
        let session = makeSession()
        LocalSessionStore.add(session: session)
        LocalSessionStore.add(session: session)
        XCTAssertEqual(LocalSessionStore.count(), 1)
        XCTAssertEqual(LocalSessionStore.completedCount(), 1)
    }

    // MARK: - Reset

    func test_clear_resetsCompletedCountToZero() {
        increment()
        increment()
        increment()
        XCTAssertEqual(LocalSessionStore.completedCount(), 3)

        LocalSessionStore.clear()

        XCTAssertEqual(LocalSessionStore.completedCount(), 0)
        XCTAssertEqual(LocalSessionStore.count(), 0)
        XCTAssertTrue(LocalSessionStore.all().isEmpty)
    }

    func test_clear_isIdempotent() {
        LocalSessionStore.clear()
        LocalSessionStore.clear()
        XCTAssertEqual(LocalSessionStore.completedCount(), 0)
    }

    func test_incrementAfterClear_startsAtOneAgain() {
        increment()
        increment()
        LocalSessionStore.clear()
        increment()
        XCTAssertEqual(LocalSessionStore.completedCount(), 1)
    }

    // MARK: - Default-field decode (isStandalone)

    func test_session_defaultsIsStandaloneToTrueWhenOmittedFromJson() throws {
        // Older rows pre-date the `is_standalone` field. They should
        // decode with `isStandalone == true` (per the comment in the
        // source).
        let legacyJson = #"""
        [{
          "id": "legacy-1",
          "technique_name": "Box Breath",
          "duration": 65,
          "completed": true,
          "timestamp": "2025-01-01T00:00:00Z"
        }]
        """#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(legacyJson.utf8)
        let sessions = try decoder.decode([LocalSessionStore.Session].self, from: data)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions.first?.isStandalone ?? false)
    }
}
