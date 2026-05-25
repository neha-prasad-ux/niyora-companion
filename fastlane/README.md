# Fastlane

## One-time operator setup

1. **Install dependencies**

   ```sh
   bundle install
   ```

2. **Set environment variables**

   ```sh
   export FASTLANE_APPLE_ID="you@example.com"
   export FASTLANE_TEAM_ID="XXXXXXXXXX"   # 10-char Apple Developer team ID
   ```

   Find your team ID at developer.apple.com/account/#!/membership.

3. **Set up signing certificates**

   ```sh
   bundle exec fastlane match init
   ```

   Choose `git` (recommended) or `appstore` (API key) as the storage backend.
   Follow the prompts to create or import certificates and provisioning profiles.

## Shipping a beta

```sh
bundle exec fastlane beta
```

This will:
- Auto-increment the build number (CFBundleVersion) from the last TestFlight build.
- Regenerate `NiyoraCompanion.xcodeproj` from `project.yml` via xcodegen.
- Build a signed `.ipa` using the `app-store` export method.
- Upload to TestFlight with the first 30 lines of `CHANGELOG.md` as the "What to Test" note.

## Shipping a release

```sh
bundle exec fastlane release
```

Uploads a new binary to App Store Connect for manual review submission.
Does not auto-submit for review.
