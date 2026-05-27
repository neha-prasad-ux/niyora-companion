import Foundation

// Tier lives in `Tiers.swift` (single canonical source of truth, ported from
// `neha-prasad-ux/niyora src/tiers.ts`). This file only defines techniques and their
// `unlockTier`.

/// HSL color for the particle renderer, stored as [hue, saturation, lightness].
struct PhaseColor: Equatable {
    let h: Double
    let s: Double
    let l: Double
}

/// Visual configuration for a technique's particle animation.
struct VisualConfig: Equatable {
    let inhaleColor: PhaseColor
    let holdColor: PhaseColor
    let exhaleColor: PhaseColor
    let motion: Motion
    let brightnessBoost: Double

    enum Motion: String, Equatable {
        case converge
        case wave
        case snowfall
        case alternate
        case lunar
        case belly
        case sedation
        case river
        case warmPulse
        case orbit
        case sensory
        case ambient
    }
}

/// One phase of a breathing technique (inhale, hold, or exhale).
struct BreathPhase: Equatable, Identifiable {
    let id = UUID()
    let type: PhaseType
    let label: String
    let duration: TimeInterval

    enum PhaseType: Equatable {
        case inhale
        case hold
        case exhale
    }
}

/// A breathing technique with timed phases and rounds.
struct BreathingTechnique: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let instructions: String
    let benefits: String
    let phases: [BreathPhase]
    let rounds: Int
    let visual: VisualConfig
    let unlockTier: Tier

    /// Total duration in seconds.
    var duration: TimeInterval {
        let oneCycle = phases.map(\.duration).reduce(0, +)
        return oneCycle * Double(rounds)
    }
}

/// A mindfulness moment with text prompts.
struct MindfulnessTechnique: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let instructions: String
    let benefits: String
    let prompts: [Prompt]
    let visual: VisualConfig
    let unlockTier: Tier

    struct Prompt: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let duration: TimeInterval
    }

    /// Total duration in seconds.
    var duration: TimeInterval {
        prompts.map(\.duration).reduce(0, +)
    }
}

/// Union type for all techniques.
enum Technique: Identifiable, Equatable {
    case breathing(BreathingTechnique)
    case mindfulness(MindfulnessTechnique)

    var id: UUID {
        switch self {
        case .breathing(let t): return t.id
        case .mindfulness(let t): return t.id
        }
    }

    var name: String {
        switch self {
        case .breathing(let t): return t.name
        case .mindfulness(let t): return t.name
        }
    }

    var subtitle: String {
        switch self {
        case .breathing(let t): return t.subtitle
        case .mindfulness(let t): return t.subtitle
        }
    }

    var instructions: String {
        switch self {
        case .breathing(let t): return t.instructions
        case .mindfulness(let t): return t.instructions
        }
    }

    var benefits: String {
        switch self {
        case .breathing(let t): return t.benefits
        case .mindfulness(let t): return t.benefits
        }
    }

    var visual: VisualConfig {
        switch self {
        case .breathing(let t): return t.visual
        case .mindfulness(let t): return t.visual
        }
    }

    var unlockTier: Tier {
        switch self {
        case .breathing(let t): return t.unlockTier
        case .mindfulness(let t): return t.unlockTier
        }
    }

    var duration: TimeInterval {
        switch self {
        case .breathing(let t): return t.duration
        case .mindfulness(let t): return t.duration
        }
    }
}

// MARK: - All techniques

/// All 14 techniques: 7 pranayama + 7 mindfulness.
let allTechniques: [Technique] = [
    // Breathing techniques
    .breathing(BreathingTechnique(
        name: "Box Breath",
        subtitle: "calms under pressure · 65s",
        instructions: "In 4, hold 4, out 4, hold 4. Steady rhythm.",
        benefits: "Let's lower your stress hormones and switch your body into rest mode.",
        phases: [
            BreathPhase(type: .inhale, label: "inhale", duration: 4),
            BreathPhase(type: .hold, label: "hold", duration: 4),
            BreathPhase(type: .exhale, label: "exhale", duration: 4),
            BreathPhase(type: .hold, label: "hold", duration: 4),
        ],
        rounds: 4,
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 230, s: 28, l: 12),
            holdColor: PhaseColor(h: 250, s: 18, l: 11),
            exhaleColor: PhaseColor(h: 210, s: 22, l: 11),
            motion: .converge,
            brightnessBoost: 0
        ),
        unlockTier: .spark
    )),
    .breathing(BreathingTechnique(
        name: "Ocean Breath",
        subtitle: "slows heart rate · 60s",
        instructions: "Soft 'haaa' sound at the back of your throat. Breathe through nose.",
        benefits: "Time to slow your heart rate and quiet those overactive brain signals.",
        phases: [
            BreathPhase(type: .inhale, label: "inhale through nose", duration: 4),
            BreathPhase(type: .exhale, label: "exhale slowly", duration: 6),
        ],
        rounds: 6,
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 185, s: 30, l: 12),
            holdColor: PhaseColor(h: 190, s: 20, l: 11),
            exhaleColor: PhaseColor(h: 175, s: 25, l: 11),
            motion: .wave,
            brightnessBoost: 0
        ),
        unlockTier: .radiance
    )),
    .breathing(BreathingTechnique(
        name: "Cooling Breath",
        subtitle: "lowers body heat · 60s",
        instructions: "Curl your tongue. Inhale through it, exhale through nose.",
        benefits: "Let's cool your body down and lower your blood pressure in just a few breaths.",
        phases: [
            BreathPhase(type: .inhale, label: "inhale through mouth", duration: 4),
            BreathPhase(type: .hold, label: "hold", duration: 2),
            BreathPhase(type: .exhale, label: "exhale through nose", duration: 6),
        ],
        rounds: 5,
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 200, s: 35, l: 13),
            holdColor: PhaseColor(h: 210, s: 20, l: 11),
            exhaleColor: PhaseColor(h: 195, s: 30, l: 10),
            motion: .snowfall,
            brightnessBoost: 0.15
        ),
        unlockTier: .glow
    )),
    .breathing(BreathingTechnique(
        name: "Alternate Nostril",
        subtitle: "reset between tasks · 75s",
        instructions: "Inhale left, exhale right. Then inhale right, exhale left.",
        benefits: "Get ready to bring both sides of your brain into sync.",
        phases: [
            BreathPhase(type: .inhale, label: "inhale left", duration: 4),
            BreathPhase(type: .hold, label: "hold", duration: 4),
            BreathPhase(type: .exhale, label: "exhale right", duration: 4),
            BreathPhase(type: .inhale, label: "inhale right", duration: 4),
            BreathPhase(type: .hold, label: "hold", duration: 4),
            BreathPhase(type: .exhale, label: "exhale left", duration: 4),
        ],
        rounds: 3,
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 270, s: 25, l: 12),
            holdColor: PhaseColor(h: 45, s: 20, l: 11),
            exhaleColor: PhaseColor(h: 280, s: 20, l: 11),
            motion: .alternate,
            brightnessBoost: 0
        ),
        unlockTier: .radiance
    )),
    .breathing(BreathingTechnique(
        name: "Left Nostril",
        subtitle: "switches into rest · 60s",
        instructions: "Press right nostril closed. Breathe in and out through the left.",
        benefits: "Let's activate your body's built-in calming system and ease you toward rest.",
        phases: [
            BreathPhase(type: .inhale, label: "inhale left", duration: 4),
            BreathPhase(type: .hold, label: "hold", duration: 2),
            BreathPhase(type: .exhale, label: "exhale right", duration: 6),
        ],
        rounds: 5,
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 220, s: 18, l: 13),
            holdColor: PhaseColor(h: 230, s: 12, l: 11),
            exhaleColor: PhaseColor(h: 215, s: 15, l: 10),
            motion: .lunar,
            brightnessBoost: 0.1
        ),
        unlockTier: .shine
    )),
    .breathing(BreathingTechnique(
        name: "Belly Breath",
        subtitle: "eases the body · 60s",
        instructions: "Let your belly rise on the in-breath, soften on the out.",
        benefits: "Let's strengthen your body's stress resilience and bring down inflammation.",
        phases: [
            BreathPhase(type: .inhale, label: "breathe into belly", duration: 4),
            BreathPhase(type: .exhale, label: "release slowly", duration: 6),
        ],
        rounds: 6,
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 90, s: 22, l: 12),
            holdColor: PhaseColor(h: 60, s: 18, l: 11),
            exhaleColor: PhaseColor(h: 35, s: 25, l: 11),
            motion: .belly,
            brightnessBoost: 0
        ),
        unlockTier: .spark
    )),
    .breathing(BreathingTechnique(
        name: "Wind Down",
        subtitle: "deep relaxation · 75s",
        instructions: "Inhale 4, hold 7, exhale 8. The long exhale is the key.",
        benefits: "Get ready to guide your nervous system into deep relaxation.",
        phases: [
            BreathPhase(type: .inhale, label: "inhale", duration: 4),
            BreathPhase(type: .hold, label: "hold", duration: 7),
            BreathPhase(type: .exhale, label: "exhale", duration: 8),
        ],
        rounds: 4,
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 260, s: 22, l: 12),
            holdColor: PhaseColor(h: 250, s: 18, l: 10),
            exhaleColor: PhaseColor(h: 245, s: 15, l: 9),
            motion: .sedation,
            brightnessBoost: 0
        ),
        unlockTier: .spark
    )),

    // Mindfulness moments
    .mindfulness(MindfulnessTechnique(
        name: "Be Kind to Yourself",
        subtitle: "softens self-criticism · 25s",
        instructions: "Read each phrase slowly. Let it land.",
        benefits: "Let's lower your stress hormones and give your mind the warmth it needs.",
        prompts: [
            MindfulnessTechnique.Prompt(text: "this is a moment of difficulty", duration: 8),
            MindfulnessTechnique.Prompt(text: "difficulty is part of being human", duration: 8),
            MindfulnessTechnique.Prompt(text: "may I be kind to myself right now", duration: 8),
        ],
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 25, s: 28, l: 12),
            holdColor: PhaseColor(h: 30, s: 22, l: 11),
            exhaleColor: PhaseColor(h: 20, s: 25, l: 11),
            motion: .warmPulse,
            brightnessBoost: 0
        ),
        unlockTier: .spark
    )),
    .mindfulness(MindfulnessTechnique(
        name: "Let It Drift",
        subtitle: "loosens stuck thoughts · 35s",
        instructions: "Notice a thought. Place it on a leaf. Watch it float away.",
        benefits: "Time to loosen the grip of those thoughts so they stop feeling like facts.",
        prompts: [
            MindfulnessTechnique.Prompt(text: "notice what's on your mind", duration: 6),
            MindfulnessTechnique.Prompt(text: "place the thought on a leaf", duration: 7),
            MindfulnessTechnique.Prompt(text: "watch it float gently downstream", duration: 8),
            MindfulnessTechnique.Prompt(text: "let the stream carry it away", duration: 7),
            MindfulnessTechnique.Prompt(text: "the stream flows on", duration: 5),
        ],
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 140, s: 22, l: 12),
            holdColor: PhaseColor(h: 150, s: 18, l: 11),
            exhaleColor: PhaseColor(h: 130, s: 20, l: 10),
            motion: .river,
            brightnessBoost: 0
        ),
        unlockTier: .shine
    )),
    .mindfulness(MindfulnessTechnique(
        name: "Bring Someone to Mind",
        subtitle: "warms the mood · 25s",
        instructions: "Picture one person who matters. Feel the warmth.",
        benefits: "Let's boost your feel-good brain chemicals and ease your body.",
        prompts: [
            MindfulnessTechnique.Prompt(text: "think of one person", duration: 8),
            MindfulnessTechnique.Prompt(text: "feel that warmth", duration: 8),
            MindfulnessTechnique.Prompt(text: "let it settle", duration: 8),
        ],
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 35, s: 30, l: 13),
            holdColor: PhaseColor(h: 40, s: 25, l: 12),
            exhaleColor: PhaseColor(h: 30, s: 28, l: 11),
            motion: .warmPulse,
            brightnessBoost: 0.1
        ),
        unlockTier: .spark
    )),
    .mindfulness(MindfulnessTechnique(
        name: "Hold Yourself",
        subtitle: "signals safety · 30s",
        instructions: "Wrap your arms around yourself. Hold gently.",
        benefits: "Let's tell your brain you're safe and release those calming hormones.",
        prompts: [
            MindfulnessTechnique.Prompt(text: "wrap your arms around yourself", duration: 6),
            MindfulnessTechnique.Prompt(text: "hold gently", duration: 8),
            MindfulnessTechnique.Prompt(text: "feel the warmth of your own care", duration: 8),
            MindfulnessTechnique.Prompt(text: "you are held", duration: 6),
        ],
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 20, s: 30, l: 13),
            holdColor: PhaseColor(h: 25, s: 25, l: 12),
            exhaleColor: PhaseColor(h: 15, s: 28, l: 11),
            motion: .converge,
            brightnessBoost: 0
        ),
        unlockTier: .spark
    )),
    .mindfulness(MindfulnessTechnique(
        name: "Kind Words",
        subtitle: "quiets the inner critic · 30s",
        instructions: "Read each line silently. Repeat it to yourself.",
        benefits: "Time to rewire how your brain talks to you about yourself.",
        prompts: [
            MindfulnessTechnique.Prompt(text: "I am enough", duration: 7),
            MindfulnessTechnique.Prompt(text: "I am doing my best", duration: 7),
            MindfulnessTechnique.Prompt(text: "I deserve kindness", duration: 7),
            MindfulnessTechnique.Prompt(text: "I am exactly where I need to be", duration: 7),
        ],
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 45, s: 25, l: 12),
            holdColor: PhaseColor(h: 50, s: 20, l: 11),
            exhaleColor: PhaseColor(h: 40, s: 22, l: 11),
            motion: .ambient,
            brightnessBoost: 0.05
        ),
        unlockTier: .spark
    )),
    .mindfulness(MindfulnessTechnique(
        name: "Five Senses",
        subtitle: "grounds you in the body · 35s",
        instructions: "Notice 5 you see, 4 you touch, 3 you hear, 2 you smell, 1 you taste.",
        benefits: "Let's pull your attention out of those spiraling thoughts and back into your body.",
        prompts: [
            MindfulnessTechnique.Prompt(text: "5 things you can see", duration: 7),
            MindfulnessTechnique.Prompt(text: "4 things you can touch", duration: 7),
            MindfulnessTechnique.Prompt(text: "3 things you can hear", duration: 7),
            MindfulnessTechnique.Prompt(text: "2 things you can smell", duration: 6),
            MindfulnessTechnique.Prompt(text: "1 thing you can taste", duration: 6),
        ],
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 160, s: 20, l: 12),
            holdColor: PhaseColor(h: 120, s: 18, l: 11),
            exhaleColor: PhaseColor(h: 80, s: 22, l: 11),
            motion: .sensory,
            brightnessBoost: 0
        ),
        unlockTier: .spark
    )),
    .mindfulness(MindfulnessTechnique(
        name: "Soft Gaze",
        subtitle: "relaxes tired eyes · 35s",
        instructions: "Soften your eyes on the centre point. Let everything else blur.",
        benefits: "Let's increase your calm brainwave activity and relieve that eye-strain tension.",
        prompts: [
            MindfulnessTechnique.Prompt(text: "soften your gaze", duration: 5),
            MindfulnessTechnique.Prompt(text: "rest your eyes on the centre", duration: 10),
            MindfulnessTechnique.Prompt(text: "let everything else blur", duration: 10),
            MindfulnessTechnique.Prompt(text: "just seeing", duration: 8),
        ],
        visual: VisualConfig(
            inhaleColor: PhaseColor(h: 270, s: 18, l: 12),
            holdColor: PhaseColor(h: 265, s: 15, l: 11),
            exhaleColor: PhaseColor(h: 275, s: 12, l: 10),
            motion: .orbit,
            brightnessBoost: 0
        ),
        unlockTier: .brilliance
    )),
]

/// Filter techniques unlocked at the given tier.
func unlockedTechniques(tier: Tier) -> [Technique] {
    let reachedTiers: Set<Tier> = {
        switch tier {
        case .spark: return [.spark]
        case .glow: return [.spark, .glow]
        case .shine: return [.spark, .glow, .shine]
        case .radiance: return [.spark, .glow, .shine, .radiance]
        case .brilliance: return [.spark, .glow, .shine, .radiance, .brilliance]
        }
    }()
    return allTechniques.filter { reachedTiers.contains($0.unlockTier) }
}
