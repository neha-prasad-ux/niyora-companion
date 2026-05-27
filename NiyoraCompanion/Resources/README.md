# Ambient Audio Files

Three ambient audio tracks are bundled with the app:

- `audio/serene.mp3` — serene ambient (~3.6 MB)
- `audio/ocean.mp3` — ocean waves ambient (~2.2 MB)
- `audio/forest.mp3` — forest sounds ambient (~2.7 MB)

Sourced from `neha-prasad-ux/niyora public/audio/` (operator-owned; licensed for use across Niyora surfaces).

These files are listed individually in `project.yml` under `resources` so XcodeGen copies them to the bundle root, where `Bundle.main.url(forResource:withExtension:)` can resolve them.

The app uses `AVAudioSession` category `.ambient` so audio respects the iOS Silent Mode switch.
