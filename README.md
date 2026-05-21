# Niyora Companion

iOS companion app for [Niyora](https://github.com/neha-prasad-ux/niyora). Captures
a 30 second stress estimate from your fingertip on the back camera, on demand,
so the Niyora Mac app can show whether breathing sessions move the needle. The
estimate is RMSSD (heart rate variability) derived from the green channel of
the camera frame with the flashlight illuminating your finger.

The earlier HealthKit-on-window path proved too sparse in real wear (the Apple
Watch logs HRV only every few minutes, often missing the 5 min window around a
session). PPG runs whenever the user taps "Measure stress" on the Mac, with
the phone visibly active, so it is a reliable source the user controls.

See `docs/hrv-companion-spec.md` in the main Niyora repo for the architecture.

## Setup

This project uses [XcodeGen](https://github.com/yonyz/XcodeGen) so the
`.xcodeproj` is generated, not committed.

```sh
brew install xcodegen
xcodegen generate
open NiyoraCompanion.xcodeproj
```

Then in Xcode:

1. Select the `NiyoraCompanion` target → Signing & Capabilities.
2. Set your **Team** (the Apple Developer account also used for the Mac app).
   You can also set `DEVELOPMENT_TEAM` in `project.yml` and re-run `xcodegen
   generate`.

## Running

A 30 second PPG capture needs a physical iPhone (the Simulator has no camera
and no torch). To exercise the full loop:

- Pair the iPhone with the Mac via the QR in the Mac app's Connect-your-iPhone
  card.
- Tap **Measure stress** on the Mac (visible on the pre-session info screen
  and on the post-session mood screen).
- The phone presents the measurement sheet. Press your fingertip lightly over
  the back camera and the flashlight; the waveform appears once the signal
  stabilises. After 30 seconds you'll see "Estimate sent."
- The Mac shows the result in the calm-score trend chart.

## Debug HRV spike

A DEBUG-only HealthKit screen lives behind the waveform button in the toolbar.
It can read HRV samples your Apple Watch logged to HealthKit, for diagnostic
comparison against the PPG estimate. It is not part of the shipping data path
and is not visible in Release builds.

## Notes

- The wire format is documented in `Protocol.swift`. The current version is
  `v2`; old Macs running v1 will fail the identify handshake with "protocol 1
  not supported."
- Nothing leaves your devices. The TCP link is local-network only; there is no
  account, no telemetry, no cloud.
