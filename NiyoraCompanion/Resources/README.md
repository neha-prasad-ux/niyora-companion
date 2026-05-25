# Ambient Audio Files

This directory should contain three ambient audio tracks in MP3 format:

- `serene.mp3` - Serene ambient track
- `ocean.mp3` - Ocean waves ambient track
- `forest.mp3` - Forest sounds ambient track

These files are referenced by `BreathSessionView` and play during breath sessions when the user selects a non-random audio option.

## Audio Requirements

- Format: MP3
- Length: 2-5 minutes (will loop)
- Volume: Normalized to prevent clipping
- Silent Mode: The app uses `.playback` category, so audio plays even when the device is in silent mode. Consider using `.ambient` if you want Silent Mode to mute the audio.

## Sourcing Audio

Use royalty-free ambient tracks from sources like:
- Epidemic Sound
- Artlist
- Free Music Archive
- YouTube Audio Library

Ensure proper licensing for distribution.
