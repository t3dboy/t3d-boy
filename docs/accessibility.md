# T3d Boy — Accessibility

T3d Boy is built to be playable by everyone — with a screen reader, with the keyboard
alone, or with motion sensitivity. This guide explains what's supported and how to use
it.

**Contents**

- [VoiceOver](#voiceover)
- [Keyboard navigation](#keyboard-navigation)
- [Reduce Motion](#reduce-motion)
- [What's announced where](#whats-announced-where)
- [A note on the game screen](#a-note-on-the-game-screen)

---

## VoiceOver

Every control in T3d Boy is exposed to **VoiceOver** with a proper name, role, and
state, and can be operated by a screen-reader user.

**Turn VoiceOver on/off:** press **⌘F5** (or triple-press the Touch ID button on some
Macs), or enable it in **System Settings ▸ Accessibility ▸ VoiceOver**.

**Navigate:** use the VoiceOver keys (Control-Option, written **VO**) with the arrow
keys — **VO-→ / VO-←** move between elements. **VO-Space** activates the focused control
(press a button, flip a toggle, open a menu).

What you'll hear, for example:

- Buttons — *"Play, button"*, *"Favourite, button"*, *"Change, button"*.
- Console tabs — *"Console, Game Boy, pop-up button."* Activating it cycles to the next
  console (Game Boy → Game Boy Color → Favourites).
- Sort control — *"Sort, Most popular by reviews, pop-up button."*
- Toggle switches — *"Hardcore Lighting, checkbox, on"* (and the state changes as you
  flip them).
- The achievements drawer handle — *"Show achievements, button"* / *"Hide achievements,
  button."*
- Box art — *"Box art for Donkey Kong, image."*
- In the **Engineer** theme, the LED counter reads as *"Total play time: 68 minutes."*

**Achievement unlocks are spoken.** When you earn an achievement, VoiceOver announces
*"Achievement unlocked: <name>, <points> points"* (and game mastery / leaderboard
results), so it isn't a purely visual notification.

**Decorative chrome is skipped.** Purely cosmetic elements — the Engineer theme's
speaker grille, hex screws, I/O-strip labels (OUTPUT/DISPLAY/SYNC…), katakana flourishes
and serial number — are hidden from VoiceOver so they don't clutter navigation.

---

## Keyboard navigation

You can operate the entire interface without a mouse.

**Enable Full Keyboard Access:** **System Settings ▸ Keyboard ▸ Keyboard navigation**
(turn it on). This lets **Tab** move focus between *all* controls, not just text fields
and lists. (Text fields, the ROM list, and standard buttons are always keyboard-reachable
regardless of this setting.)

Then:

- **Tab / ⇧Tab** — move focus forward / backward through the controls. A **focus ring**
  shows exactly where you are.
- **Space / Return** — activate the focused control (press a button, flip a toggle, open
  the sort or theme menu).
- **← / →** (or ↑ / ↓) — on the **console tabs**, move between Game Boy / Color /
  Favourites.
- **Arrow keys** — in the ROM list, move the selection up and down.

The game itself is played with the keyboard too — see
[Controls](user-guide.md#controls).

---

## Reduce Motion

If you've turned on **System Settings ▸ Accessibility ▸ Display ▸ Reduce Motion**, T3d
Boy honours it: the "power-on" launch zoom and the power-off animation **snap** to their
final state instead of animating, and other transitions are shortened. The power-switch
sound still plays.

---

## What's announced where

| Area | Accessible as |
|---|---|
| Console tabs | One pop-up button announcing the current console; activating cycles |
| Sort control | Pop-up button with the current sort as its value |
| Play / Favourite / Change | Buttons |
| ROM list | Standard table — rows read their title and stats; arrow keys move selection |
| Box art | Image, labelled with the current game |
| Effect & settings toggles | Checkboxes with on/off state and a spoken name |
| Theme picker | Standard radio buttons (Classic / Pistachio / Engineer / Liquid Glass) |
| Achievements drawer handle | Button ("Show/Hide achievements") |
| Sign-in form, sliders, popups | Native macOS controls (fully accessible) |
| Achievement unlocks | Spoken announcements |

> **Low vision:** the **Liquid Glass** theme makes the app see-through, which lowers text
> contrast over a busy desktop. For maximum legibility, use **Classic** (which follows
> your system light/dark and accent settings) or **Engineer** (high-contrast dark text on
> a light body). The box art and game screen stay solid in every theme.

---

## T3d Tunes

The **T3d Tunes** bar that opens the instrument is a standard keyboard- and VoiceOver-
accessible button, as are the sound dropdowns and the **Use FX** and per-lane **Glide**
switches (each carries a VoiceOver label). The **keyboard** can be played without a pointer:
its keys are mapped to the computer keyboard (`Q`–`P`, then `A`–`L`, then `Z`–`N`) whenever
the drawer is open and you're not editing a text field. The step grid and the rotary knobs
are still a **mouse/pointer-oriented** surface that isn't yet exposed to VoiceOver or
focus-based keyboard navigation; making the whole sequencer playable without a pointer is a
planned follow-up.

---

## A note on the game screen

The emulated game picture is, by nature, a visual medium — a Game Boy game's screen
can't be meaningfully described by a screen reader. Accessibility here covers everything
*around* the game: browsing and choosing games, configuring the emulator, tracking
achievements, and launching/exiting play. Audio (game sound, the boot chime, the
power-switch click, and achievement-unlock chimes) plays normally.

---

*Found an accessibility gap? It's worth reporting — the goal is for T3d Boy to be
playable by all.*
