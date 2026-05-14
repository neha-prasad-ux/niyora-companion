# Niyora Companion

iOS companion app for [Niyora](https://github.com/neha-prasad-ux/niyora). Reads
Heart Rate Variability (HRV) from HealthKit so the Niyora Mac app can show
whether breathing sessions actually help you relax.

HealthKit does not exist on macOS, so this small iOS app is the only sanctioned
way to get HRV (which the Apple Watch records and the iPhone stores). See
`docs/hrv-companion-spec.md` in the main Niyora repo for the full architecture.

## Status

**Milestones 1-2: HealthKit spike.** This build only proves we can authorize
and read HRV. There is no Mac sync yet — that is milestones 3+.

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
3. The **HealthKit** capability is already declared in
   `NiyoraCompanion/NiyoraCompanion.entitlements`.

## Running

HealthKit HRV **cannot be tested in the Simulator** — there is no HRV data
there. You need:

- A physical iPhone, signed in to your Apple ID.
- An Apple Watch paired to it, worn long enough to have logged HRV samples
  (check the Health app → Browse → Heart → Heart Rate Variability).

Build to the iPhone, tap **Allow HRV access**, accept the permission sheet,
then **Read HRV** over a window. If real numbers appear, the spike is proven.

## Notes

- HealthKit never tells an app whether *read* access was granted — only whether
  the permission sheet was shown. An empty result is ambiguous: it could mean
  "denied" or "no data." The UI says this plainly.
- HRV is sparse. A short window may legitimately contain zero samples.
