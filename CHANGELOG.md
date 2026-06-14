# Changelog

All notable changes to T3d Boy. This project uses [semantic versioning](https://semver.org).

## [1.3.0] — 2026-06-14

### Added
- **Focused launch experience** — selecting a game powers the console on: it zooms
  out of the chosen box art, expands to a larger play size, and dims everything
  behind, with a synthesized DMG power‑switch click. The game window is chrome‑free
  so nothing competes with the screen, and Exit powers off the same way (click +
  zoom back into the art).
- **In‑game control bar** — a subtle, translucent bar at the bottom of the game with
  Hardcore Lighting, Worm Light, Full Screen, and Exit. It and the achievements
  drawer's reveal handle appear on mouse movement and fade away while you play.
- **Full screen** for the game window.
- **T3d LCD Real Feel™** — recreates an old LCD's pixel persistence by blending each
  frame with the previous one. Games that faked transparency by flickering pixels
  every frame (e.g. Donkey Kong's attract demo) now render as the intended steady,
  semi‑transparent image instead of harsh strobing. On by default, alongside
  Hardcore Lighting and Worm Light.

### Changed
- The emulator screen now scales to fit — a larger focused play size and full‑screen
  support — instead of a fixed window size.

## [1.2.1] — 2026-06-13

### Fixed
- **Screen tearing in Game Boy Color games.** The PPU now double-buffers — it renders
  into a back buffer and publishes the completed frame at VBlank, so the display can
  never show a half-drawn frame.

### Added
- **Optional FPS counter** — a small readout (with a mini T3d) in the game window's
  top-right corner. Turn it on in Preferences ▸ Appearance ▸ Display.

## [1.2.0] — 2026-06-13

### Added
- **RetroAchievements** — optional sign-in to track unlocks, points, leaderboards,
  rich presence, and mastery for Game Boy and Game Boy Color games, built on the
  official rcheevos library. See [docs/retroachievements.md](docs/retroachievements.md).
- **Achievements drawer** — a trophy-tabbed panel that slides out on the right of both
  the ROM library and the game window. Browse a game's full achievement list (with
  badges, descriptions, points, type chips, search, sorting, and Core/Unofficial
  grouping) before you play, and watch unlocks and progress live while you do. Hidden
  by default; pop it out with the handle, or set it to open automatically.
- **Hardcore mode** — opt into RetroAchievements' stricter ruleset, which disables
  save-state loads (and, in future, rewind/slow-motion/cheats). A "disable hardcore
  for this session" escape lets you continue without losing your saved preference.
- **In-game unlock toasts** with an optional chime, volume control, and configurable
  screen corner.
- **Preferences (⌘,) window** with a RetroAchievements section (account, hardcore,
  drawer default, unlock sound, notification position, connection test) and an
  Appearance section.
- The library now **remembers your last-selected game** across window close/reopen
  and app launches.

### Changed
- The app now **defaults to dark mode** (switchable to light in Preferences ▸
  Appearance).
- The dark-mode toggle moved from the library to **Preferences ▸ Appearance**, so the
  artwork panel sits flush at the bottom.
- The ambient-dimming effect "Hardcore Mode" was renamed **Hardcore Lighting** to
  avoid confusion with RetroAchievements hardcore mode (⌃⌘H is unchanged).
- Refreshed the app icon.

### Security
- Your RetroAchievements password is never stored — only the login token is kept, in
  the macOS Keychain.

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
