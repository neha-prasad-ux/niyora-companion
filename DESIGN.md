# DESIGN.md

The visual, interaction, and tonal language for the Niyora iOS companion app.

> This is the iOS adaptation of [DESIGN.md in the Mac repo](https://github.com/neha-prasad-ux/niyora/blob/main/DESIGN.md). The brand promise, voice, tier colors, and technique catalogue are shared. This file covers iOS-specific rendering, haptics, ProMotion, and accessibility.

## Brand promise

> Calm in 60 seconds. Privacy-first. Nothing leaves your devices.

Three claims, in this order:
1. The product is fast, small, and finishes in a minute.
2. The product respects you.
3. The product earns trust through architecture, not promises.

Every interaction decision should reinforce at least one of these. If a change doesn't, it probably should not ship.

## Voice and copy

Identical to the Mac repo's design language:

- Quiet, not chirpy. No exclamation points. No "Yay!" or "Great job!"
- Direct, not preachy. State what's happening. Trust the user.
- No motivational mantras. "You've got this!" is out.
- No em dashes. Use periods, commas, or middle dots (`·`).
- No emojis in body copy (UI labels, phase instructions). The visuals are the cue.

## The five Soul tiers

Tier colors are cross-repo canonical. They MUST stay byte-identical to `niyora/src/tiers.ts` and `NiyoraCompanion/Tiers.swift`. Changing one value requires updating all three files plus the web orb in `niyora-web`.

| Tier | Hue (HSL) | Saturation | Sessions threshold | Feeling |
|---|---:|---:|---:|---|
| Spark | 30 | 70% | 0 | First flame, beginner energy |
| Glow | 335 | 70% | 5 | Settled, regular practice |
| Shine | 280 | 65% | 15 | Confidence, deeper work |
| Radiance | 230 | 65% | 40 | Steady, embodied |
| Brilliance | 210 | 60% | 80 | Quiet mastery |

Brightness is 90% for all tiers. Tier progression is based on completed session count (frequency and recency), not technique difficulty. See `Tiers.swift`.

The cross-repo tier-colour-sync contract is tracked in neha-prasad-ux/niyora-companion#19.

## Breathing techniques

Seven pranayama practices, each with its own visual motion and particle personality:

| Name | Tier | Phase pattern (s) | Motion style |
|---|---|---|---|
| Box Breath | Spark | inhale 4, hold 4, exhale 4, hold 4 | converge |
| Belly Breath | Spark | inhale 4, exhale 6 | belly |
| Wind Down (4-7-8) | Spark | inhale 4, hold 7, exhale 8 | sedation |
| Cooling Breath (Sheetali) | Glow | inhale 4, hold 2, exhale 6 | snowfall |
| Left Nostril | Shine | inhale 4, hold 2, exhale 6 | lunar |
| Ocean Breath (Ujjayi) | Radiance | inhale 4, exhale 6 | wave |
| Alternate Nostril (Naadishodhana) | Radiance | inhale L 4, hold 4, exhale R 4, inhale R 4, hold 4, exhale L 4 | alternate |

## Mindfulness practices

Seven non-breathing moments grounded in CBT, self-compassion, and grounding research:

| Name | Tier | Research basis | Motion style |
|---|---|---|---|
| Be Kind to Yourself | Spark | Neff 2003, self-compassion | warmPulse |
| Bring Someone to Mind | Spark | Gratitude research | warmPulse |
| Hold Yourself | Spark | Somatic self-soothing | converge |
| Kind Words | Spark | Affirmation and self-talk | ambient |
| Five Senses (5-4-3-2-1) | Spark | Grounding, clinical CBT | sensory |
| Let It Drift | Shine | CBT thought defusion | river |
| Soft Gaze (Trataka) | Brilliance | Talwadkar 2014 | orbit |

All 14 practices share the same `Technique` type hierarchy in `Techniques.swift`. Names, phase timings, and tier assignments are canonical and must match the Mac app.

## Audio

Set `AVAudioSession` category to `.ambient` so Silent Mode mutes the app. Do not use `.playback`; it overrides the mute switch and is the wrong choice for a stress-relief tool.

**Existing violation**: `BreathSessionView.swift:329` currently uses `.playback`. This is a known bug. Do not copy the pattern.

## Haptic design

Haptics reinforce the breath phases on iPhone only (guard with `UIDevice.current.userInterfaceIdiom == .phone`):

- **Inhale**: light impact (`UIImpactFeedbackGenerator(style: .light)`) at the start of each inhale phase.
- **Hold**: no haptic. Silence is the cue for stillness.
- **Exhale**: medium impact (`UIImpactFeedbackGenerator(style: .medium)`) at the start of each exhale phase.

Haptics must have an off path. When `UIAccessibility.isHapticsEnabled` is false or the user has disabled haptics in Settings, skip all haptic calls silently.

## Visual language

### Background and depth

- App background: near-black with a faint indigo cast.
- Particle animations use the `VisualConfig` colors from each technique definition in `Techniques.swift`. Colors respond to the current breath phase.
- The breathing canvas fills the full screen during a session; chrome is minimal.

### Color use

- Tier colors come from the user's progression (see tier table above), not arbitrary accent choices.
- Avoid hard accent colors outside tier hues. Errors and warnings use soft red/amber variants.
- Body text contrast at minimum 4.5:1 (WCAG AA).
- Color is never the only way to convey state: pair tier color with tier name, not color alone.

### Typography

- **SF Pro Rounded**: tier labels, large display text, orb ring counters.
- **SF Pro Text**: body copy, phase instructions, phase labels.
- Both scale with iOS Dynamic Type. Do not hard-code point sizes. Use semantic text styles (`.body`, `.headline`, `.title`) and let the system scale them.
- Line height: 1.6 for body, 1.2 for headings.

### ProMotion

Animate at up to 120 Hz on ProMotion-capable devices and 60 Hz on others. Use `CADisplayLink` with `preferredFramesPerSecond = 0` to let the system select the optimal rate. Do not hard-code `1/60` as a frame interval.

### Motion

- Breath cycle cadence drives animation timing. Easing should feel like an inhale, not a bounce.
- Respect `UIAccessibility.isReduceMotionEnabled`. When true, reduce or disable particle animation; fall back to a simple opacity fade.
- No animation should outlast a single breath cycle.

## Interaction grammar

- One primary action per screen. Either "Begin," or the close gesture. Never two equal-weight buttons.
- Swipe down to dismiss the measurement sheet. Tap outside the breathing canvas to return to the home screen.
- No carousel, no modal stack outside the measurement sheet.
- No account creation. No email collection. No "share with a friend" CTA.

## Accessibility

- Respect `UIAccessibility.isReduceMotionEnabled`: scale down or disable particle animation when set.
- Respect `UIAccessibility.isHapticsEnabled`: skip all `UIImpactFeedbackGenerator` calls when false.
- Every interactive control has an `.accessibilityLabel` and `.accessibilityHint`.
- SF Pro scales with Dynamic Type automatically. Do not suppress it with fixed sizes.
- Test with VoiceOver on a physical device before each release.

## Privacy in the visual

The privacy promise must be visible in the product, not just the README:

- No remote content rendered in the app.
- No "share to" buttons that imply network reach.
- The pairing QR scan is the only camera use the user initiates for a non-PPG purpose; make the scope clear in the UI copy.

## What's intentionally absent

- A streak counter or "you missed yesterday" screens.
- Achievements, badges, leaderboards.
- Social features.
- AI avatars or coach voices.
- Cloud sync.
- Push notification reminders (handled by the Mac app).

If a future PR proposes one of these, it should justify the addition against this list, not simply assume it is wanted.
