import XCTest
@testable import NiyoraCompanion

/// Tests for `Tier.current(completedSessions:)` boundary behavior.
///
/// Canonical thresholds (from `Tiers.swift`):
///   spark      = 0
///   glow       = 5
///   shine      = 15
///   radiance   = 40
///   brilliance = 80
final class TiersTests: XCTestCase {

    // MARK: - Zero / negative sessions

    func test_zeroSessions_isSpark() {
        XCTAssertEqual(Tier.current(completedSessions: 0), .spark)
    }

    func test_negativeSessions_clampsToSpark() {
        // Defensive: a negative count should never escalate past spark.
        XCTAssertEqual(Tier.current(completedSessions: -1), .spark)
        XCTAssertEqual(Tier.current(completedSessions: -100), .spark)
    }

    // MARK: - Just-below each threshold

    func test_justBelowGlow_isSpark() {
        XCTAssertEqual(Tier.current(completedSessions: 4), .spark)
    }

    func test_justBelowShine_isGlow() {
        XCTAssertEqual(Tier.current(completedSessions: 14), .glow)
    }

    func test_justBelowRadiance_isShine() {
        XCTAssertEqual(Tier.current(completedSessions: 39), .shine)
    }

    func test_justBelowBrilliance_isRadiance() {
        XCTAssertEqual(Tier.current(completedSessions: 79), .radiance)
    }

    // MARK: - Exactly-at each threshold

    func test_exactlyAtSpark_isSpark() {
        XCTAssertEqual(Tier.current(completedSessions: 0), .spark)
    }

    func test_exactlyAtGlow_isGlow() {
        XCTAssertEqual(Tier.current(completedSessions: 5), .glow)
    }

    func test_exactlyAtShine_isShine() {
        XCTAssertEqual(Tier.current(completedSessions: 15), .shine)
    }

    func test_exactlyAtRadiance_isRadiance() {
        XCTAssertEqual(Tier.current(completedSessions: 40), .radiance)
    }

    func test_exactlyAtBrilliance_isBrilliance() {
        XCTAssertEqual(Tier.current(completedSessions: 80), .brilliance)
    }

    // MARK: - Way-above

    func test_wayAboveBrilliance_isBrilliance() {
        XCTAssertEqual(Tier.current(completedSessions: 81), .brilliance)
        XCTAssertEqual(Tier.current(completedSessions: 1_000), .brilliance)
        XCTAssertEqual(Tier.current(completedSessions: 1_000_000), .brilliance)
    }

    // MARK: - Mid-range sanity

    func test_midRangeBetweenGlowAndShine_isGlow() {
        XCTAssertEqual(Tier.current(completedSessions: 10), .glow)
    }

    func test_midRangeBetweenShineAndRadiance_isShine() {
        XCTAssertEqual(Tier.current(completedSessions: 25), .shine)
    }

    func test_midRangeBetweenRadianceAndBrilliance_isRadiance() {
        XCTAssertEqual(Tier.current(completedSessions: 60), .radiance)
    }

    // MARK: - Alias parity

    func test_forSessionCount_matchesCurrent() {
        for n in [0, 4, 5, 14, 15, 39, 40, 79, 80, 200] {
            XCTAssertEqual(
                Tier.forSessionCount(n),
                Tier.current(completedSessions: n),
                "alias diverged at n=\(n)"
            )
        }
    }

    // MARK: - sessionsToNext

    func test_sessionsToNext_fromSpark() {
        XCTAssertEqual(Tier.spark.sessionsToNext(currentCount: 0), 5)
        XCTAssertEqual(Tier.spark.sessionsToNext(currentCount: 4), 1)
        XCTAssertEqual(Tier.spark.sessionsToNext(currentCount: 5), 0)
    }

    func test_sessionsToNext_fromBrilliance_isNil() {
        XCTAssertNil(Tier.brilliance.sessionsToNext(currentCount: 100))
    }
}
