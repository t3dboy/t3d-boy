# Changelog

All notable changes to T3d Boy. This project uses [semantic versioning](https://semver.org).

## [3.3.0] — 2026-06-20

A big T3d Tunes expansion — generative sequencing, GB-authentic synthesis, and a live looper.

![T3d Tunes — the looping chiptune instrument](https://raw.githubusercontent.com/t3dboy/t3d-boy/main/tools/screenshot-tunes.png)

### Added
- **Live looping, per-row.** Every sequencer lane has its own **REC** button: it **banks** the
  lane's current grid pattern into a loop and clears the grid, while the loop keeps playing
  (banked steps show as **dots**). Bank again to **stack layers** — steps banked twice get two
  dots. **⌥-click / right-click REC** clears that lane's loop. The banked loop is
  **independent of the step grid**: the main **Clear** now wipes only the grid and keeps
  playing, so loops carry on while you build something new underneath. The **Perform** tab adds
  global controls — **Tap** tempo, a hold-to-roll **Stutter** pad, a tempo-synced **Pump**
  (sidechain duck), and **Clear All Loops**.
- **Feature-panel tabs** below the keyboard, spread the full width of the window:
  - **Rhythm** — per-lane **Length** (polymeter), playback **Direction** (forward / reverse /
    ping-pong / random), step **Probability**, **Euclidean** fill, and a **Mutate** button.
  - **Timbre** — per-lane **Arpeggiator** (chord shapes on one mono channel), **PWM** (pulse
    duty sweep), **Vibrato**, and **Ratchets** (per-step retriggers / rolls).
  - **Visual** — a draggable **wavetable editor** for the wave channel (with Sine/Saw/Square
    presets) and **Export WAV** (records one loop of the live, FX'd output to a file).
  - **ROM** — **Auto-compose** a starter loop from the cartridge's harvested sounds, per-lane
    **Sound-shuffle**, and a two-game **Mashup** that blends a second ROM's sounds in.

  Rhythm and Timbre lay their controls out as **four channel cards** — a quarter each for PUL1,
  PUL2, WAVE and NOIS — so every channel has room for full-size knobs and controls.
- **A live oscilloscope** in the top-right: opening the drawer reflows the strip above it into
  the game's box art, its details, and a scope drawing the instrument's output waveform.
- **Per-step pitch** via the keyboard, and the grid now shows banked-loop layers as dots.

### Changed
- Opening T3d Tunes now expands it to **fill the window**, overlaying the library so the
  sequencer gets real room — while the console tabs and ROM list stay visible at the top so
  you can still switch games.
- The synth panels were given consistent, roomier, full-width layouts.

## [3.2.0] — 2026-06-19

### Added
- **Capture box art from the game** — a new art button (🖼) on the in-game control bar
  saves the screen you're currently on as that ROM's box art. Useful when the
  auto-generated cover caught a publisher logo or a blank frame instead of the title
  screen: get to the screen you want, click the button, and the library cover updates
  instantly.

### Fixed
- **Play Game no longer stops working after you exit a game.** Recording playtime on exit
  refreshed the ROM list, which cleared the table selection — so the next Play press had no
  selected game and silently did nothing. The selection is now preserved across the refresh.

## [3.1.1] — 2026-06-19

### Fixed
- **The T3d Tunes keyboard no longer triggers the macOS alert beep** when played from the
  computer keyboard. The key-event monitor wasn't actually consuming mapped keystrokes, so
  each note also fell through to the system as an unhandled key.

## [3.1.0] — 2026-06-19

T3d Tunes grows up — a full synth FX rack, per-lane glide, and a playable keyboard.

### Added
- **Synth FX rack** on the sequencer transport — six knobs colouring the whole instrument:
  **Cutoff** (resonant low-pass) and **Res** (resonance), **Drive** (drive/bit-crush),
  **Delay** (tempo-synced echo), **Reverb** (hall), and **Swing** (groove on the off-beats).
  They run as a real signal chain on the output, so they shape the loop and the keyboard.
- **Per-lane Glide** — a portamento switch on each pitched lane (Pulse 1, Pulse 2, Wave) that
  slides the pitch between consecutive notes.
- **Playable keyboard** — a two-octave (C3–C5) keyboard replaces the old pad soundboard. A
  **Keyboard** dropdown picks any sound from the whole sampled library, and a **Use FX**
  switch plays it dry or through the FX knobs.
  - **Computer-keyboard mapping** — every key has a shortcut, mapped chromatically from C3:
    `QWERTYUIOP`, then `ASDFGHJKL`, then `ZXCVBN`. The bound letter is printed on each key.
- **Reset** (↺) button — returns every FX knob, Swing, all Glide switches and the per-lane
  pitch knobs to their defaults, and flushes any delay/reverb tail.
- **Dice** (🎲) button — randomises the pattern across all four lanes.

### Changed
- The sequencer's play button is now **Play Sequencer** (and the library's is **Play Game**),
  to tell them apart.
- Pitch and FX knobs are easier to turn — drag *or* scroll-wheel, a larger hit target, and
  the conventional rest position (lowest fully left, highest fully right).

### Fixed
- Clearing or stopping the sequencer now fully flushes the delay/reverb tails, so nothing
  keeps ringing in the background.

## [3.0.0] — 2026-06-19

A major release built around **T3d Tunes** — the Game Boy's sound chip as a playable
instrument.

### Added
- **T3d Tunes** — a looping chiptune synth/soundboard, detached from the emulator. A drawer
  slides up from the bottom of the library (full-width **T3d Tunes** bar) with a
  boutique-synth-style 16-step looper across the four Game Boy channels (Pulse 1, Pulse 2,
  Wave, Noise):
  - **Samples the selected ROM's sounds** — runs the game headlessly and captures the
    distinct instrument "recipes" it uses (pulse duty + envelope, the wave channel's custom
    wavetables, noise tones), then offers them per channel.
  - **Per-channel sound dropdowns** to pick which of the ROM's sounds each lane plays, a
    step grid, pitch knobs, mute, a live pad soundboard, and transport (play/stop, BPM).
  - **Browse-to-swap** — selecting another game keeps the loop running and swaps in that
    game's sounds, so you can audition the whole library musically.
  - Themed across all four looks (Classic / Pistachio / Engineer / Liquid Glass).
  - How it works, and a full primer on Game Boy audio:
    **[docs/sound-chip.md](docs/sound-chip.md)**.

## [2.3.1] — 2026-06-18

### Changed
- **T3d Boy Light is Game Boy only now.** The Game Boy Light never existed for the Game
  Boy Color, so the effect no longer applies to GBC games: selecting a Game Boy Color ROM
  automatically deselects T3d Boy Light and disables its toggle, and the effect is
  unavailable in-game (the control-bar button and ⌃⌘B) for colour titles. It remains
  available for Game Boy games.

## [2.3.0] — 2026-06-18

### Added
- **T3d Boy Light** — a new screen effect (⌃⌘B): *"Only popular in Japan, an
  electroluminescent teal blue glowing display."* It recreates the **Game Boy Light**'s
  EL backlight — the screen glows an even teal/cyan-green, recolouring the picture while
  keeping its light/dark detail so games stay readable, brightest in the centre and
  falling off to a gently darker teal vignette at the edges, like the real panel.

### Removed
- **Road Trip Mode** — removed. Due to just not being very good and generally being a bad
  idea from inception. T3d Boy Light takes its place in the effects panel, the in-game
  control bar, and on ⌃⌘B.

## [2.2.0] — 2026-06-16

### Added
- **Liquid Glass theme** — a fourth theme, and a loving parody of Apple's glass design
  language. Thought Apple's implementation of Liquid Glass was bad? T3d Boy takes it to
  another level of let-down: the whole app turns into a see-through sheet of glass — the
  Mac desktop shows straight through the window — and the buttons are glass too, slowly
  *melting*, with droplets drooling off their bottom edges. The box art and the game
  screen stay solid so they're always readable. Pick it in Preferences ▸ Appearance ▸
  Theme.
- **Update notifications** — T3d Boy can check GitHub for a newer release and let you
  know with a tap on the shoulder from T3d the mascot, showing the new version and its
  changelog with **Download**, **Ignore for Now**, or **Stop reminding me about this
  version** (which silences just that release — future ones still notify). It runs on
  launch (turn it off in Preferences ▸ Appearance ▸ *Check for updates automatically*),
  or check any time from **T3d Boy ▸ Check for Updates…**. The check is HTTPS-only and
  never downloads or installs anything on its own — clicking Download just opens the
  release in your browser.

## [2.1.1] — 2026-06-14

A security-hardening release focused on RetroAchievements sign-in and credential storage.

### Security
- Your saved RetroAchievements login token is now **device-bound** — it never syncs to
  iCloud Keychain or moves to another device through a backup. (You'll be asked to sign
  in once more after updating.)
- **All RetroAchievements traffic is enforced HTTPS-only** at the app level, so
  credentials can never travel over an unencrypted connection.
- The app now ships with the **hardened runtime**, protecting the running app against
  memory inspection by other processes.
- The development-only plaintext-token path is no longer compiled into release builds at
  all.

## [2.1.0] — 2026-06-14

### Added
- **Road Trip Mode** — a new screen effect: the late-night car ride. The screen goes dark
  and the only light is streetlights — soft rounded pools that sweep down across the
  screen on random angles, with dark gaps between. Turning it on switches Worm Light on
  (and locks it) so you can still read the screen. Toggle ⌃⌘B.

### Changed
- **Hardcore Lighting now checks the hardware.** It needs an ambient-light reading, which
  not every Mac can provide (e.g. a desktop Mac with a plain monitor). Where it can't, the
  option is disabled with a subtle "Not compatible with this device" note under its
  description instead of silently doing nothing. See the
  [supported devices](docs/user-guide.md#hardcore-lighting--supported-devices) list.

### Fixed
- Keyboard focus rings no longer appear when you click a control with the mouse — they
  show only when navigating by keyboard, as intended.

## [2.0.0] — 2026-06-14

A major release built around **themes** and a top-to-bottom **accessibility** pass.

### Added
- **Themes** — three complete looks, switchable live in Preferences ▸ Appearance ▸ Theme:
  - **Classic** — the clean, system-native macOS look (light or dark).
  - **Pistachio** *(default)* — a warm soft-dark skin with rounded type, coral accents
    and a pistachio palette.
  - **Engineer** — a boutique-synth-style hardware look: a sandblasted light-grey
    "device" body with orange rubber keys, red-LED read-outs, monospaced uppercase type,
    a drilled speaker grille, hex screws and katakana labels. Includes a live LED counter
    of your **total minutes played** across every game. (Light-only by design.)
  - See [docs/themes section of the user guide](docs/user-guide.md#themes).
- **Accessibility** — the app is now usable without a mouse or without sight:
  - **VoiceOver** — every control announces its name, role and state, and can be
    activated by a screen-reader user; achievement unlocks are spoken.
  - **Full keyboard navigation** — Tab to any control, a focus ring shows where you are,
    and Space/Return/arrows operate it.
  - **Reduce Motion** — the launch/exit animations snap instead of zooming when the
    system setting is on.
  - See [docs/accessibility.md](docs/accessibility.md).

### Changed
- **Preferences redesigned** — a System Settings-style sidebar window grouped into
  Achievements (account, options, notifications), Screen Effects, and Appearance.
  Checkboxes are now toggle switches that match the rest of the UI.
- The **achievements drawer's "Sign in" prompt** now opens the in-app login
  (Preferences ▸ Achievements) instead of the RetroAchievements website.

### Fixed
- **RetroAchievements hardcore integrity** — switching a game from softcore to
  hardcore mid-session now resets the game, so a run can't be promoted to hardcore
  after progress was made with softcore conveniences. Every server request now also
  carries a proper, versioned client identifier.
- Selected ROM-list rows and sidebar items stay legible on every theme, even when the
  window isn't focused.

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
