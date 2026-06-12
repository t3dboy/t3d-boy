# Changelog

All notable changes to T3d Boy. This project uses [semantic versioning](https://semver.org).

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
