# Roadmap

Living doc. Items move left to right: **Idea → In Progress → Done → Next update → Released**. **Parked** is a side track for ideas decided against or deferred, with a reason. Item numbers are stable IDs; they do not change when an item moves between columns.

- **Done**: merged on `main`, no release plan yet.
- **Next update**: queued for the upcoming release.
- **Released**: live on TestFlight or App Store.

## Idea

| # | Item | Notes |
|---|---|---|
| - | CI / Fastlane pipeline | Automated build, test, and TestFlight upload on every merge to `main`. |
| - | Settings screen polish | Preferred technique picker, haptic on/off toggle. |
| - | Session history tab | View past session counts and tier progression over time. |
| - | Onboarding first-launch pointer | One-time overlay explaining the tab structure on first open. |

## In Progress

Items in progress for v1 (standalone breathing and mindfulness, no Mac pairing required by default):

| # | Item | Notes |
|---|---|---|
| 9 | RootTabView + Breath + My Soul + Onboarding + Reminders | Full v1 standalone feature set: tab bar, breathing session flow, My Soul tier panel, first-launch onboarding, local reminders. Tracked in #9. |

## Done

Merged on `main`, no release decision yet.

| # | Item | Notes |
|---|---|---|
| 40 | My Soul + home bottom padding | Orb fills full iPhone screen; My Soul gradient matches Niyora brand; safe-area padding applied. |
| 38 | CFBundleDisplayName set to "Niyora" | App label on home screen and Spotlight shows "Niyora," not "NiyoraCompanion." |
| 33 | Orb constrained to 240pt + safe-area clearance | Consistent with brand proportions; bottom nav bar no longer overlaps the orb. |

## Next update

Queued for v1.x after standalone v1 ships:

| # | Item | Notes |
|---|---|---|
| 17 | os.Logger migration | Replace `print()` calls with `os.Logger` per CLAUDE.md logging rules. Subsystem: `com.niyora.companion`. |
| 18 | Bundled ambient audio | Ship mp3 assets; re-enable the Resources folder in `project.yml`. |
| 19 | Tier-colour-sync enforcement | Cross-repo check that `Tiers.swift`, `niyora/src/tiers.ts`, and the web orb stay byte-identical on every PR. |
| 20 | Paired-mode tier sync | Receive tier-level updates from the Mac when in paired mode. Depends on #19. |
| - | CI / Fastlane | Automated build + TestFlight on merge to `main`. |

## Released

Live to users.

| # | Item | Notes |
|---|---|---|
| _none_ | | |

## Parked

| # | Item | Reason |
|---|---|---|
| - | PPG / HRV measurement | Requires physical device testing and the full Mac pairing stack. Deferred until v1 standalone ships. |
| - | HealthKit integration | PPG is the primary measurement path. HealthKit reads are debug-only and intentionally gated behind `#if DEBUG`. No plan to expose them in the shipping build. |
| - | watchOS companion | Blocked on shipping iOS standalone first. Architecture spec lives in `docs/hrv-companion-spec.md` in the main Niyora repo. |
| - | Multi-Mac pairing | Single-Mac pairing covers v1 needs. Multi-Mac adds protocol complexity without demonstrated user demand. |
| - | History merge on pair | Needs a stable local storage format first. Deferred. |
| - | iPhone-upgrade history preservation | Requires iCloud backup or a local export path. No account exists; approach TBD. |
