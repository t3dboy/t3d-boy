# Changelog

All notable changes to T3d Boy. This project uses [semantic versioning](https://semver.org).

## [1.1.0] — 2026-06-13

### Added
- **Hardcore Mode** — recreates the original Game Boy's non-backlit screen: the
  emulator dims based on ambient light (read from the display brightness sensor),
  so a dark room makes the screen hard to see, just like the real DMG. Toggle in
  the library's lighting panel or Game → Hardcore Mode (⌃⌘H).
- **Worm Light** — a warm, angled '90s clip-on light rendered over the screen to
  help you see in the dark, like the accessories of the era. Game → Worm Light (⌃⌘L).
- Lighting panel under the box art with both toggles; the artwork previews the
  effects live and reacts to your room's lighting.
- Aim the Worm Light by dragging it on the game preview display — the warm pool
  follows and stretches into a grazing-angle ellipse, and a running game updates live.

## [1.0.0] — 2026-06-12

First release.

### Added
- Game Boy (DMG) and Game Boy Color emulation: SM83 CPU, scanline PPU, timers,
  interrupts, OAM DMA, HDMA, double-speed mode, MBC1/2/3/5 cartridges
- Audio: all four APU channels with stereo panning
- ROM library: auto-generated box art, GB / GBC / Favourites tabs, sorting by
  name / review score / play time, per-game play-time and play-count tracking
- Per-system ROM folders (separate Game Boy and Game Boy Color libraries)
- Save states (5 slots per game), pause, and the T3d boot screen with chime
- Game controller support via Apple's GameController framework
- Light / dark mode and a guided onboarding flow with T3d the mascot
