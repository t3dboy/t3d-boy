# T3d Boy — User Guide

A complete walkthrough of every feature in T3d Boy, a native macOS Game Boy and
Game Boy Color emulator.

**Contents**

- [First launch](#first-launch)
- [The ROM library](#the-rom-library)
- [Playing a game](#playing-a-game)
- [Controls](#controls)
- [Save states & pause](#save-states--pause)
- [Display effects](#display-effects)
- [Themes](#themes)
- [RetroAchievements](#retroachievements)
- [Accessibility](#accessibility)
- [Preferences reference](#preferences-reference)
- [Menus & keyboard shortcuts](#menus--keyboard-shortcuts)
- [Tips & troubleshooting](#tips--troubleshooting)

---

## First launch

T3d Boy ships with **no games** — Game Boy ROMs are copyrighted, so you supply your
own `.gb`, `.gbc`, or zipped ROM files.

On the very first launch, **T3d** (the pixel mascot) walks you through a short setup:

1. **Choose your ROM folders.** You can point the **Game Boy** and **Game Boy Color**
   tabs at the same folder (T3d Boy sorts games into the right tab by reading each
   cartridge's header) or at two separate folders.
2. **Generate box art.** T3d Boy boots each game headlessly, captures its title
   screen, and caches it as the game's "box art." This runs in parallel and only
   happens once per game; you can keep using the app while it finishes.

You can re-run box-art generation any time from **File ▸ Generate Missing Box Art…**

---

## The ROM library

The library window is your home screen. On the left is the game list; on the right is
the selected game's art, stats, and the **Play** button.

- **Tabs** — switch between **Game Boy**, **Game Boy Color**, and **Favourites**.
- **Sort** — use the Sort control to order by **Most popular by reviews**,
  **Name (A–Z)**, or **Most played**.
- **Favourite a game** — select it and press **☆ Favourite** (it then appears in the
  Favourites tab). Press again to unfavourite.
- **Play-time tracking** — each game shows how long you've played it and how many
  times, alongside a community review score (♥).
- **Change folder** — the strip at the bottom of the list shows the current tab's ROM
  folder; press **Change** to pick a different one. (Also **File ▸ Change Folder for
  Current Tab…**)
- T3d Boy remembers your **last selected game** between launches.

---

## Playing a game

Select a game and press **Play** (or double-click it in the list, or press Return).

The game doesn't just open in a window — it **powers on**: the screen zooms out of the
box art, expands to a comfortable play size, dims everything behind it, and plays a
synthesized DMG power-switch *click*. The play window is deliberately chrome-free so
nothing competes with the game.

**The in-game control bar.** Move the mouse and a subtle translucent bar fades in at
the bottom of the window:

| Button | What it does |
|---|---|
| ☀ Hardcore Lighting | Toggle ambient-light dimming |
| 🔦 Worm Light | Toggle the clip-on light |
| ⤢ Full Screen | Enter / leave full screen |
| ⏻ Exit | Power the game off (reverse zoom + click) and return to the library |

The bar — and the achievements drawer's reveal handle — auto-hide after a couple of
seconds of no mouse movement so they never distract from play.

---

## Controls

| Game Boy | Keyboard | Game controller |
|----------|----------|-----------------|
| D-pad | Arrow keys | D-pad / left stick |
| A / B | Z / X | Circle / Cross (east / south) |
| Start | Return | Menu / Options |
| Select | Shift | Share |
| Pause | Space | — |
| Save / load state | ⌘1–5 / ⇧⌘1–5 | — |

**Game controllers** connect over Bluetooth via Apple's GameController framework —
DualShock, DualSense, Xbox, and Switch Pro controllers are all supported. Just pair the
controller with your Mac; T3d Boy picks it up automatically.

---

## Save states & pause

- **Save state** — **⌘1** through **⌘5** save to one of five slots per game.
- **Load state** — **⇧⌘1** through **⇧⌘5** restore the matching slot.
- **Pause** — press **Space** in the game window (or **Game ▸ Pause**, ⌘P).

> Save states are also available from the **Game** menu. Note: while RetroAchievements
> **hardcore mode** is on, loading a save state is blocked (you'll be offered the choice
> to disable hardcore for the session). See [RetroAchievements](#retroachievements).

---

## Display effects

Three optional effects recreate the feel of original hardware. Toggle them in the
library's effects panel, in the in-game control bar, or in **Preferences ▸ Screen
Effects**.

- **Hardcore Lighting** (⌃⌘H) — recreates the non-backlit original DMG by dimming the
  screen to match your **room's ambient light** (read from the Mac's ambient light
  sensor). The brighter your room, the brighter the screen — just like the real thing.
- **Worm Light** (⌃⌘L) — a warm, aimable '90s-style clip-on lamp that reflects across
  the screen so you can see in the dark. **Drag the glowing bulb** on the game's box-art
  preview in the library to change the angle; the new angle applies everywhere,
  including any game already running.
- **T3d LCD Real Feel™** — blends each frame with the previous one to recreate an old
  LCD's pixel persistence ("ghosting"). Games that faked transparency by flickering
  pixels every other frame (e.g. some attract-mode demos) render as the intended steady,
  semi-transparent image instead of harsh strobing. On by default.

---

## Themes

Give the whole app a different look from **Preferences ▸ Appearance ▸ Theme**. Switching
is instant — the library and Preferences windows restyle live.

### Classic
The clean, system-native macOS look. Follows your **Dark mode** preference (toggle it in
Preferences ▸ Appearance, or **View ▸ Toggle Dark Mode**, ⇧⌘D).

### Pistachio *(default)*
A warm, soft-dark "friendly" skin: rounded type, coral accents, a pistachio-green
palette, and pill-style toggle switches. Pistachio uses its own colour palette, so the
**Dark mode** toggle is disabled while it's selected.

### Engineer
A boutique-synth-inspired *hardware* look — the library becomes a physical-feeling
device:

- a sandblasted **light-grey body** with an engraved header plate, a near-black **I/O
  strip**, a drilled **speaker grille**, and **hex screws**;
- **orange rubber keys** (Play, the console tabs), a **white** Favourite key, and **red
  seven-segment LED** read-outs for scores and status;
- **monospaced UPPERCASE** type and small **katakana** accents;
- a live red-LED counter in the top-left showing your **total minutes played** across
  every game and console (with an orange 分 — "minutes" — glyph) that ticks up as you
  play.

Engineer is a light-only theme, so the **Dark mode** toggle is disabled while it's
selected.

> **Switching themes keeps you in place** — if you change theme from the Appearance tab,
> Preferences stays on the Appearance tab afterwards.

---

## RetroAchievements

T3d Boy integrates the [RetroAchievements](https://retroachievements.org) service so you
can earn achievements, points, leaderboard entries, and game "mastery."

- **Sign in** at **Preferences ▸ Achievements ▸ Account** (or click *"Sign in to track
  your progress"* in the achievements drawer). Only a login **token** is stored, in your
  macOS Keychain — never your password.
- **The achievements drawer** — click the **trophy handle** on the right edge of the
  library (to browse a game's achievements before playing) or in-game. It shows each
  achievement's art, points, description, and your progress.
- **Notifications** — unlocks pop up as toasts; choose the corner and an optional unlock
  sound in **Preferences ▸ Achievements ▸ Notifications**.
- **Hardcore mode** (optional) — disables save-state loading, rewind, slow-motion and
  cheats for "legit" unlocks. Switching a game to hardcore mid-session restarts it so a
  run can't be promoted after using softcore conveniences.

Full details: **[docs/retroachievements.md](retroachievements.md)**.

---

## Accessibility

T3d Boy supports **VoiceOver**, **full keyboard navigation** (Tab + focus rings), and
**Reduce Motion**, so it's playable without a mouse or without sight.

See the dedicated guide: **[docs/accessibility.md](accessibility.md)**.

---

## Preferences reference

Open with **⌘,**. The sidebar groups settings into three sections:

**Achievements**
- *Account* — sign in / out of RetroAchievements.
- *Options* — Hardcore mode; show the achievements drawer by default; Test Connection.
- *Notifications* — play a sound on unlock; unlock volume; notification position.

**Screen Effects**
- Hardcore Lighting, Worm Light, T3d LCD Real Feel™ (each with a one-line description).

**Appearance**
- *Theme* — Classic / Pistachio / Engineer.
- *Dark mode* — light or dark (Classic only; disabled for themes with a fixed palette).
- *Show the FPS counter in the game window*.

---

## Menus & keyboard shortcuts

| Action | Shortcut |
|---|---|
| Preferences | ⌘, |
| ROM Library | ⌘L |
| Open ROM… | ⌘O |
| Pause | Space (in game) / ⌘P |
| Save state (slots 1–5) | ⌘1 – ⌘5 |
| Load state (slots 1–5) | ⇧⌘1 – ⇧⌘5 |
| Hardcore Lighting | ⌃⌘H |
| Worm Light | ⌃⌘L |
| Toggle Dark Mode | ⇧⌘D |

---

## Tips & troubleshooting

- **A game is in the wrong tab.** Tabs are split by the cartridge's CGB header flag. If
  two tabs point at one folder, the split is automatic; if they point at separate
  folders, each tab shows its own folder's contents.
- **No box art for a game.** Run **File ▸ Generate Missing Box Art…** Art is cached, so
  it only needs generating once.
- **Worm Light is pointing the wrong way.** Drag the glowing bulb on the box-art preview
  in the library to re-aim it.
- **Can't load a save state.** Hardcore mode blocks save-state loading; turn it off in
  Preferences ▸ Achievements, or accept the "disable hardcore for this session" prompt.
- **Installing the app** (first-launch security warning) and **supplying ROMs** are
  covered in the main [README](../README.md).
