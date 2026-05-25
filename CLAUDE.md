# CLAUDE.md

Notes for Claude Code and other agents working on this repo.

> For shared conventions (commit format, review discipline, copy voice, no em dashes), see [CLAUDE.md in the Mac repo](https://github.com/neha-prasad-ux/niyora/blob/main/CLAUDE.md). This file adds iOS-specific rules on top of those.

## Quick orientation

- **What this is**: the Niyora iOS companion app. SwiftUI + Swift, iOS 17+.
- **What it does right now**: captures a 30-second fingertip PPG stress estimate on demand, sends the RMSSD result to the Mac over local TCP, and provides a standalone breathing and mindfulness session flow.
- **What it is not**: a HealthKit reader, a cloud service, or a standalone wellness tracker. The privacy rules from the Mac repo apply here too.

## Branching and commit discipline (hard rule)

**Never commit to `main`. Never push to `main`. No exceptions.** The workflow is always: branch, commit, PR, maintainer merges.

Agents use branches named `lucius/<issue>-<timestamp>`. Never amend commits on a shared branch. Never force-push.

## Project setup

The `.xcodeproj` is generated, not committed. After every edit to `project.yml`:

```sh
xcodegen generate
```

Never hand-edit `NiyoraCompanion.xcodeproj`. The file is a build artifact; any manual edit will be overwritten on the next `xcodegen generate` run.

## Logging

Use `os.Logger` for all diagnostics. Never `print()`.

- **Subsystem**: `com.niyora.companion`
- **Categories**: `ppg.capture`, `ppg.signal`, `pairing`, `protocol`, `persistence`, `ui`

```swift
import os
private let logger = Logger(subsystem: "com.niyora.companion", category: "ppg.capture")
logger.debug("frame count: \(frameCount)")
```

The `print()` migration is tracked in neha-prasad-ux/niyora-companion#17.

## Feature flags

`NIYORA_V1_PPG_ENABLED` gates the Mac-pairing and PPG capture flow. Default OFF for the v1 standalone build. Do not enable it unless the full pairing handshake, TCP protocol, and PPG pipeline are present and tested on a physical device.

## Privacy rules

- No HealthKit reads in the shipping data path. HealthKit access exists only in the DEBUG spike screen (`HRVSpikeView.swift`) and must not appear in Release builds.
- No third-party crash reporting SDKs. No analytics SDKs.
- No data leaves the device except over the local-network TCP link to the paired Mac. The local-network usage string in `project.yml` covers this.

## Audio

Set `AVAudioSession` category to `.ambient` so Silent Mode mutes the app. Do not set `.playback`; that overrides the mute switch and is the wrong choice for a stress-relief tool.

## Haptics

Use `UIImpactFeedbackGenerator` only on iPhone (not iPad or other form factors):

```swift
guard UIDevice.current.userInterfaceIdiom == .phone else { return }
```

## Binary assets

Every binary asset committed to the repo must be under 5 MB. Surface larger files (audio, video) via build-time download or an operator upload step. The ambient audio work is tracked in neha-prasad-ux/niyora-companion#18.

## Default workflow

1. Read `README.md`, `DESIGN.md`, and `ROADMAP.md` before nontrivial changes.
2. Branch per the rule above.
3. Run `xcodegen generate` after any `project.yml` edit.
4. Build and test on a physical iPhone for anything touching camera, torch, haptics, or local networking. The Simulator cannot run PPG capture.
5. PR with a tight description (what, why, how to test).

## House rules

These are on top of the shared rules in the Mac repo's CLAUDE.md.

- **No em dashes** in any output the user will see: commit messages, code comments, copy strings, PR descriptions. Use periods, commas, or middle dots (`·`).
- **No "I think we should also..." tangents.** Stick to the requested change. If you spot something else worth fixing, mention it in one line at the end and let the user decide.
- **No comments that narrate what the code does.** A comment must justify WHY, not describe WHAT.
- **No error handling for cases that can't happen.** Trust Swift's type system and internal invariants; only validate at system boundaries (user input, network data).

## Things that are easy to get wrong

- **`xcodegen generate` after every `project.yml` change.** A stale `.xcodeproj` causes build failures or silently excludes new files.
- **`Tiers.swift` hue and saturation values must match `niyora/src/tiers.ts`.** They are cross-repo canonical. If you change one, change all three files (Mac, iOS, web orb). See DESIGN.md for the table.
- **`Protocol.swift` `protocolVersion` is currently `v2`.** Old Macs on `v1` will fail the handshake. Do not bump the version without updating the Mac side.
- **`HRVSpikeView.swift` must not appear in Release builds.** It is gated by `#if DEBUG`. Do not remove that gate.
- **The local-network entitlement in `NiyoraCompanion.entitlements` is required for Bonjour.** Removing it breaks Mac discovery.
- **`AVAudioSession` category must stay `.ambient`.** Changing it to `.playback` overrides the mute switch.
- **Haptic calls need the iPhone idiom guard.** `UIImpactFeedbackGenerator` on iPad logs a warning and may behave unexpectedly. Always guard.

## What lives where

| You want to change... | Open this |
|---|---|
| Breathing session animation | `BreathSessionView.swift` |
| Breathing and mindfulness technique definitions | `Techniques.swift` |
| Soul tier definitions and thresholds | `Tiers.swift` |
| My Soul tab | `MySoulTabView.swift` |
| Root tab bar | `RootTabView.swift` |
| Breath tab home screen | `BreathHomeView.swift` |
| Settings view | `SettingsView.swift` |
| Pairing (QR scan + handshake) | `PairingFlow.swift`, `QRScannerView.swift` |
| TCP connection to Mac | `MacConnection.swift` |
| Wire protocol | `Protocol.swift` |
| PPG capture (camera + torch) | `PPGCapture.swift`, `MeasurementController.swift` |
| PPG signal processing | `PPGSignalProcessor.swift` |
| Waveform display | `WaveformView.swift` |
| Measurement sheet | `MeasurementSheet.swift` |
| Local session storage | `LocalSessionStore.swift` |
| Local measurement storage | `LocalMeasurementStore.swift` |
| Known Mac servers list | `KnownServerStore.swift` |
| Keychain operations | `KeychainStore.swift` |
| App entry point | `NiyoraCompanionApp.swift` |
| Debug HealthKit screen (DEBUG only) | `HRVSpikeView.swift` |
| XcodeGen project definition | `project.yml` |

## When you're unsure

- Stop and ask. The founder is non-technical; one focused question beats a wall of context.
- For anything touching privacy, local networking, or signing entitlements, default to the more conservative option.
- If you cannot test on a physical device, say so explicitly. Do not claim a fix works because it type-checks.
