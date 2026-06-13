# RetroAchievements

T3d Boy integrates [RetroAchievements](https://retroachievements.org) for Game Boy
and Game Boy Color games, using the official [rcheevos](https://github.com/RetroAchievements/rcheevos)
library. Sign in once and your unlocks, points, leaderboards, and mastery progress
are tracked as you play — and you can browse a game's achievements before you start.

It's entirely optional: if you never sign in, T3d Boy behaves exactly as before.

## Signing in

You can sign in two ways:

- **During onboarding** — the first-run wizard has an optional "Achievements" step.
- **Any time** — open **Preferences (⌘,) → RetroAchievements → Account** and enter
  your RetroAchievements username and password, or follow the link to create an
  account at retroachievements.org.

Your **password is never stored**. T3d Boy exchanges it for a login token once, then
keeps only that token in the macOS **Keychain**, so it signs you back in silently on
the next launch. Use **Sign Out** to forget the token.

## The achievements drawer

A slim tab with a 🏆 trophy sits on the right edge of both the **ROM library** and the
**game window**. Click it to slide the drawer out (the chevron points the way), and
again to tuck it away. It's hidden by default so it never distracts you while playing —
flip *Show the achievements drawer by default* in Preferences if you'd rather it always
open.

The drawer shows, for the selected or running game:

- Box art, title, console badge, total points, and a completion ring
- Rich presence (what you're currently doing) and any active leaderboard trackers
- Every achievement with its badge, description, points, and type (progression,
  missable, win condition), grouped into Core / Unofficial sections
- Live unlock state and progress as you play
- A search box and sort options (default, locked first, by points, recently unlocked)

In the library you can browse a game's full achievement list **before playing**.
Signed out, the drawer still tells you whether a game is recognised and invites you
to sign in (the achievement list itself requires an account).

## Hardcore mode

Hardcore mode mirrors RetroAchievements' stricter ruleset. Turn it on in
**Preferences → RetroAchievements**. While it's active, T3d Boy disables anything
that would undermine a legitimate run:

- Loading save states (saving is still allowed)
- Rewind, slow-motion, and cheats

If you try a blocked action, T3d Boy offers to **disable hardcore for the current
session** so you can continue. That keeps your saved preference intact — hardcore
returns the next time you launch.

## Settings

Everything lives in **Preferences (⌘,) → RetroAchievements**:

| Setting | What it does |
|---|---|
| Account | Sign in / out; shows your username and points |
| Hardcore mode | Enables the stricter ruleset described above |
| Show the achievements drawer by default | Opens the drawer automatically with each window |
| Play a sound when an achievement unlocks | Plays a chime on unlock |
| Unlock volume | Volume for that chime |
| Notification position | Which corner unlock toasts appear in |
| Test Connection | Checks that the RetroAchievements server is reachable |

## Notes

- **Game Boy / Game Boy Color only** for now. The achievement subsystem is built so
  other consoles can be added later.
- T3d Boy is not (yet) a registered RetroAchievements client, so the drawer shows an
  "Unknown Emulator" notice and **hardcore unlocks are not submitted to the server**.
  Achievements still load and display, and progress is tracked locally.
