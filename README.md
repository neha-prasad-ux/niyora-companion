# Niyora Companion

iOS app for [Niyora](https://github.com/neha-prasad-ux/niyora). Privacy-first
breathwork and stress reset. Nothing leaves your device.

## What this is

Two products in one codebase, gated by a build flag:

**v1 (shipping)** · Standalone breathing app for iPhone. The home screen
presents a single pre-session card with a pearly orb, one technique pick,
and a single Begin button. Tap Begin · 60 seconds of guided breath · done.
My Soul lives behind the top-left profile icon for tracking practice
history and tier progression. No accounts. No cloud. No analytics.

**v2 (behind `NIYORA_V1_PPG_ENABLED`)** · Pairs with the Niyora Mac app
over local wifi for a 30 second PPG (camera + flashlight) stress estimate.
Used by the Mac app's "before · after" calm-score loop. Source is intact;
flip the build flag in `project.yml` to ship it.

## Setup

This project uses [XcodeGen](https://github.com/yonyz/XcodeGen) so the
`.xcodeproj` is generated, not committed.

```sh
brew install xcodegen
cd ios
xcodegen generate
open NiyoraCompanion.xcodeproj
```

Then in Xcode:

1. Select the `NiyoraCompanion` target → Signing & Capabilities.
2. Set your **Team** (the Apple Developer account also used for the Mac app).
   You can also set `DEVELOPMENT_TEAM` in `project.yml` and re-run
   `xcodegen generate`.

## Running

### v1 (Simulator OK)

The v1 surface (Breath + My Soul) works in the iOS Simulator. Build, run,
tap Begin · the session plays the orb + audio loop for the technique's
duration, then returns you home with the count incremented.

### v2 PPG capture (requires physical iPhone)

A 30 second PPG capture needs the back camera and torch, which the
Simulator does not have. To exercise the full v2 loop with the Mac app:

- Enable the build flag: in `project.yml`, add
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS: NIYORA_V1_PPG_ENABLED` under the
  target's debug settings, then re-run `xcodegen generate`.
- Pair the iPhone with the Mac via the QR in the Mac app's
  Connect-your-iPhone card.
- Tap **Measure stress** on the Mac.
- The phone presents the measurement sheet. Press your fingertip lightly
  over the back camera and the flashlight; the waveform appears once the
  signal stabilises. After 30 seconds you'll see "Estimate sent."
- The Mac shows the result in the calm-score trend chart.

## Testing

```sh
# Unit tests
xcodebuild -project NiyoraCompanion.xcodeproj \
  -scheme NiyoraCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Test coverage:

- **Unit** · `NiyoraCompanionTests/` exercises pure-Swift logic with no
  UIKit dependencies: `Tier.current` math, technique unlocks, session
  store counting, keychain round-trips, known-server CRUD, model codec,
  PPG signal processing math, wire protocol parsing, and the two state
  machines (`MeasurementController`, `PairingFlow`).
- **UI** · `NiyoraCompanionUITests/` launches the app on the simulator
  and asserts the home screen renders the orb, the BEGIN button, and the
  technique label. Hits the rotate button to confirm Try-a-different-one
  works.

## CI

`.github/workflows/ios-ci.yml` runs unit + UI tests on every PR against
a GitHub-hosted macOS runner with iPhone 17 Pro simulator. PRs cannot
merge if CI fails.

## Project structure

```
NiyoraCompanion/
  NiyoraCompanionApp.swift      App entry point
  RootTabView.swift             v1 root (just BreathHomeView)
  ContentView.swift             v2 root (PPG + pairing, gated)

  BreathHomeView.swift          v1 home screen
  BreathSessionView.swift       60s breath session
  BreathTabView.swift           v0 list view (deprecated by BreathHomeView)
  MySoulTabView.swift           Tier display + practice history

  Techniques.swift              All breath + mindfulness practices
  Tiers.swift                   Soul tier progression math
  Models.swift                  Wire-format types
  Protocol.swift                Mac↔iPhone frame parsing

  LocalSessionStore.swift       Session count persistence (UserDefaults)
  LocalMeasurementStore.swift   Last measurement persistence
  KnownServerStore.swift        Paired Macs list
  KeychainStore.swift           Wire-protocol secrets

  PPGCapture.swift              Camera/torch session for v2
  PPGSignalProcessor.swift      Green-channel waveform → RMSSD
  WaveformView.swift            Live PPG visualisation
  MeasurementController.swift   v2 measurement state machine
  MeasurementSheet.swift        v2 measurement UI

  MacConnection.swift           TCP wire link
  PairingFlow.swift             v2 pairing state machine
  QRScannerView.swift           v2 pairing QR scanner
  CameraPreview.swift           Camera preview UIKit bridge

  HealthKitManager.swift        v2 debug HealthKit spike (DEBUG only)
  HRVSpikeView.swift            DEBUG-only Watch HRV inspector
```

## Branching · PR · merge

Same hard rule as the main Niyora repo: **never commit to `main`.**

```sh
git checkout -b feat/<slug>
# work
git push -u origin feat/<slug>
gh pr create --title "..." --body "..."
```

The maintainer (Neha) reviews and merges. CI must be green.

## Notes

- The wire format is documented in `Protocol.swift`. The current version is
  `v2`; old Macs running v1 will fail the identify handshake with
  "protocol 1 not supported."
- Nothing leaves your devices. The TCP link is local-network only; there
  is no account, no telemetry, no cloud.
