import XCTest
@testable import NiyoraCompanion

/// Tests for `unlockedTechniques(tier:)` and the `allTechniques` library.
///
/// Distribution by `unlockTier` (from `Techniques.swift`):
///   spark      = 8  (Box Breath, Belly Breath, Wind Down,
///                    Be Kind to Yourself, Bring Someone to Mind,
///                    Hold Yourself, Kind Words, Five Senses)
///   glow       = 1  (Cooling Breath)
///   shine      = 2  (Left Nostril, Let It Drift)
///   radiance   = 2  (Ocean Breath, Alternate Nostril)
///   brilliance = 1  (Soft Gaze)
/// Cumulative unlocks: 8 -> 9 -> 11 -> 13 -> 14.
final class TechniquesTests: XCTestCase {

    // MARK: - Library shape

    func test_allTechniques_hasFourteenEntries() {
        XCTAssertEqual(allTechniques.count, 14)
    }

    func test_allTechniques_haveSevenBreathingAndSevenMindfulness() {
        var breathing = 0
        var mindfulness = 0
        for technique in allTechniques {
            switch technique {
            case .breathing: breathing += 1
            case .mindfulness: mindfulness += 1
            }
        }
        XCTAssertEqual(breathing, 7, "expected 7 pranayama techniques")
        XCTAssertEqual(mindfulness, 7, "expected 7 mindfulness moments")
    }

    func test_allTechniques_haveUniqueNames() {
        let names = allTechniques.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "duplicate technique names: \(names)")
    }

    func test_allTechniques_haveUniqueIDs() {
        let ids = allTechniques.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate technique ids")
    }

    // MARK: - Per-technique invariants

    func test_everyTechnique_hasNonEmptyName() {
        for technique in allTechniques {
            XCTAssertFalse(
                technique.name.trimmingCharacters(in: .whitespaces).isEmpty,
                "empty name in \(technique)"
            )
        }
    }

    func test_everyTechnique_hasNonEmptySubtitle() {
        for technique in allTechniques {
            XCTAssertFalse(
                technique.subtitle.trimmingCharacters(in: .whitespaces).isEmpty,
                "empty subtitle for \(technique.name)"
            )
        }
    }

    func test_everyTechnique_hasNonEmptyInstructions() {
        for technique in allTechniques {
            XCTAssertFalse(
                technique.instructions.trimmingCharacters(in: .whitespaces).isEmpty,
                "empty instructions for \(technique.name)"
            )
        }
    }

    func test_everyTechnique_hasNonEmptyBenefits() {
        for technique in allTechniques {
            XCTAssertFalse(
                technique.benefits.trimmingCharacters(in: .whitespaces).isEmpty,
                "empty benefits for \(technique.name)"
            )
        }
    }

    func test_everySubtitle_containsMiddleDotFormattedDuration() {
        // Subtitle pattern is "<descriptor> · <N>s" — middle dot U+00B7.
        let middleDot = "\u{00B7}"
        for technique in allTechniques {
            XCTAssertTrue(
                technique.subtitle.contains(middleDot),
                "subtitle missing middle dot for \(technique.name): \(technique.subtitle)"
            )
            XCTAssertTrue(
                technique.subtitle.hasSuffix("s"),
                "subtitle should end in 's' (seconds) for \(technique.name): \(technique.subtitle)"
            )
        }
    }

    func test_everyTechnique_hasPositiveDuration() {
        for technique in allTechniques {
            XCTAssertGreaterThan(
                technique.duration,
                0,
                "non-positive duration for \(technique.name)"
            )
        }
    }

    // MARK: - Breathing-specific invariants

    func test_everyBreathingTechnique_hasAtLeastOnePhaseAndRoundsAboveZero() {
        for technique in allTechniques {
            guard case .breathing(let b) = technique else { continue }
            XCTAssertFalse(b.phases.isEmpty, "no phases for \(b.name)")
            XCTAssertGreaterThan(b.rounds, 0, "non-positive rounds for \(b.name)")
            for phase in b.phases {
                XCTAssertGreaterThan(
                    phase.duration,
                    0,
                    "non-positive phase duration in \(b.name)"
                )
            }
        }
    }

    // MARK: - Mindfulness-specific invariants

    func test_everyMindfulnessTechnique_hasAtLeastOnePrompt() {
        for technique in allTechniques {
            guard case .mindfulness(let m) = technique else { continue }
            XCTAssertFalse(m.prompts.isEmpty, "no prompts for \(m.name)")
            for prompt in m.prompts {
                XCTAssertGreaterThan(
                    prompt.duration,
                    0,
                    "non-positive prompt duration in \(m.name)"
                )
                XCTAssertFalse(
                    prompt.text.trimmingCharacters(in: .whitespaces).isEmpty,
                    "empty prompt text in \(m.name)"
                )
            }
        }
    }

    // MARK: - unlockedTechniques(tier:) counts

    func test_unlocked_atSpark_isEight() {
        XCTAssertEqual(unlockedTechniques(tier: .spark).count, 8)
    }

    func test_unlocked_atGlow_isNine() {
        XCTAssertEqual(unlockedTechniques(tier: .glow).count, 9)
    }

    func test_unlocked_atShine_isEleven() {
        XCTAssertEqual(unlockedTechniques(tier: .shine).count, 11)
    }

    func test_unlocked_atRadiance_isThirteen() {
        XCTAssertEqual(unlockedTechniques(tier: .radiance).count, 13)
    }

    func test_unlocked_atBrilliance_isAllFourteen() {
        XCTAssertEqual(unlockedTechniques(tier: .brilliance).count, allTechniques.count)
    }

    // MARK: - Unlock monotonicity

    func test_unlocked_isMonotonicallyNonDecreasingAcrossTiers() {
        let counts = Tier.allCases.map { unlockedTechniques(tier: $0).count }
        for i in 1..<counts.count {
            XCTAssertGreaterThanOrEqual(
                counts[i],
                counts[i - 1],
                "unlocked count decreased from \(Tier.allCases[i - 1]) to \(Tier.allCases[i])"
            )
        }
    }

    func test_unlocked_eachTierStrictlyAddsAtLeastOneTechnique() {
        // Every tier should unlock at least one new technique.
        let counts = Tier.allCases.map { unlockedTechniques(tier: $0).count }
        for i in 1..<counts.count {
            XCTAssertGreaterThan(
                counts[i],
                counts[i - 1],
                "tier \(Tier.allCases[i]) did not unlock anything new"
            )
        }
    }

    func test_lowerTierUnlocks_areSubsetOfHigherTierUnlocks() {
        for i in 1..<Tier.allCases.count {
            let lower = Set(unlockedTechniques(tier: Tier.allCases[i - 1]).map(\.id))
            let higher = Set(unlockedTechniques(tier: Tier.allCases[i]).map(\.id))
            XCTAssertTrue(
                lower.isSubset(of: higher),
                "\(Tier.allCases[i - 1]) unlocks not contained in \(Tier.allCases[i])"
            )
        }
    }

    // MARK: - Technique equality

    func test_techniqueEquality_sameInstanceIsEqual() {
        guard let first = allTechniques.first else {
            return XCTFail("allTechniques is empty")
        }
        XCTAssertEqual(first, first)
    }

    func test_techniqueEquality_differentTechniquesAreNotEqual() {
        guard allTechniques.count >= 2 else {
            return XCTFail("need at least 2 techniques")
        }
        XCTAssertNotEqual(allTechniques[0], allTechniques[1])
    }

    func test_techniqueEquality_breathingNotEqualToMindfulness() {
        let breathing = allTechniques.first { if case .breathing = $0 { return true } else { return false } }
        let mindfulness = allTechniques.first { if case .mindfulness = $0 { return true } else { return false } }
        guard let b = breathing, let m = mindfulness else {
            return XCTFail("expected at least one of each kind")
        }
        XCTAssertNotEqual(b, m)
    }
}
