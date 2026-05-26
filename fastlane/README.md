# Fastlane

## One-time operator setup

1. **Install dependencies**

   ```sh
   bundle install
   ```

2. **Set environment variables**

   Both `beta` and `release` lanes call `latest_testflight_build_number` and
   `upload_to_testflight`, which require authenticated App Store Connect access.
   Use an App Store Connect API key (recommended for CI -- no 2FA prompt):

   ```sh
   export ASC_KEY_ID="XXXXXXXXXX"          # Key ID from App Store Connect
   export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # Issuer ID
   export ASC_KEY_CONTENT="$(base64 -i AuthKey_XXXXXXXXXX.p8)"  # base64-encoded .p8
   export FASTLANE_APPLE_ID="you@example.com"
   export FASTLANE_TEAM_ID="XXXXXXXXXX"   # App Store Connect team ID (Appfile)
   export APPLE_TEAM_ID="XXXXXXXXXX"      # 10-char Apple Developer team ID (Xcode code signing)
   ```

   To generate an API key: App Store Connect -> Users and Access -> Integrations ->
   App Store Connect API -> generate a key with App Manager role. Download the `.p8`
   once (it cannot be re-downloaded). The Key ID and Issuer ID are shown on the same
   page.

   Find your team ID at developer.apple.com/account/#!/membership.

3. **Set up signing certificates**

   `fastlane/Matchfile` is committed and configured for git storage. Export the
   certificates repository URL before running match:

   ```sh
   export MATCH_GIT_URL="git@github.com:your-org/niyora-certs.git"
   ```

   Fetch (or create) the distribution certificates and profiles:

   ```sh
   bundle exec fastlane match appstore
   ```

   You must run this before either lane. `match appstore` clones the certs repo
   and installs certificates and profiles into the local Keychain.

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
