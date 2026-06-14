# T3d Boy — Style & Theming Guide

T3d Boy has a single source of truth for its look & feel: **`Sources/Theme.swift`**.
Every screen reads *semantic tokens* (`theme.accent`, `theme.surfaceRaised`,
`theme.fontTitle`) instead of hardcoding colours, fonts, radii or materials. A whole
new visual identity is therefore one `Theme` value — not an edit to every view.

## How it fits together

- **`Theme`** — a value type holding the token set (colours, materials, type scale,
  metrics, motion). See the doc comments in `Theme.swift` for what each token means.
- **`Theme.classic`** — the baseline. System-driven and dark/light adaptive; it
  reproduces the app's original appearance. Treat it as the reference, never delete it.
- **`ThemeManager.shared`** — registry of available themes, the current selection
  (persisted under `selectedTheme`), and `select(id:)` / `register(_:)`. Switching
  posts `.themeChanged`.
- **`theme`** — global accessor (`theme.accent`, etc.). Use it everywhere.
- **`ThemedUI`** — factories for the common pieces (`title`, `sectionHeader`,
  `caption`, `card`, `separator`). Build from these instead of styling inline.

Users pick the active theme in **Preferences ▸ Appearance ▸ Theme**.

## Authoring a new theme

1. Add a `static let` on `Theme` (copy `classic`, change token values).
2. `ThemeManager.shared.register(.yourTheme)` at launch (in `App.swift`).
3. It appears automatically in the Appearance picker.

```swift
extension Theme {
    static let official = Theme(
        id: "official",
        name: "Official",
        accent: NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1), // from mockup
        // …fill the remaining tokens from the mockup spec table below
    )
}
```

## Consuming the theme in a screen

- Colours: `view.layer?.backgroundColor = theme.surfaceRaised.cgColor`
- Text: `label.font = theme.fontBody; label.textColor = theme.textPrimary`
  (or just `ThemedUI.title(_:)` / `.caption(_:)`)
- Radii: `layer?.cornerRadius = theme.radiusMedium`
- Materials: `effectView.material = theme.sidebarMaterial`
- Motion: `NSAnimationContext`… `context.duration = theme.animMedium`
- **React to live switches:** observe `.themeChanged` and rebuild/restyle. See
  `PreferencesWindowController.rebuildForTheme()` for the reference pattern.

`PreferencesWindow.swift` is the **reference consumer** — every other screen should
follow its patterns when migrated.

## Mockup → token spec table

Fill this in from the official mockups; it becomes `Theme.official`.

| Token | Meaning | Value (from mockup) |
|---|---|---|
| `accent` | primary tint (buttons, selection, active toggles) | |
| `onAccent` | text/icon on an accent fill | |
| `textPrimary` | body & titles | |
| `textSecondary` | captions, subtitles, inactive icons | |
| `separator` | hairlines | |
| `surface` | window background | |
| `surfaceRaised` | cards, rows, housings | |
| `selection` | selected list-row fill | |
| `star` / `warm` / `cool` | accents (favourite star, hardcore lighting, etc.) | |
| `sidebarMaterial` / `hudMaterial` | translucency | |
| `fontTitle` / `fontSectionHeader` / `fontBody` / `fontCaption` / `fontMonoSmall` | type scale | |
| `radiusSmall` / `radiusMedium` / `radiusLarge` | corner radii | |
| `spacing` / `spacingLarge` | base unit / gutter | |
| `animFast` / `animMedium` | motion durations | |

## Migration order (when applying a new theme app-wide)

1. **`Theme.swift`** — define the new theme + register it. *(done: engine exists)*
2. **Library** (`Library.swift`) — the vertical slice; restyle fully, review, then fan out.
3. **Emulator + control bar** (`EmulatorWindow.swift`, `GameControlBar.swift`).
4. **Drawer** (`Achievements/AchievementsDrawer*`), **toasts**, **login form**.
5. **Preferences** — already a themed consumer.
6. **Motion pass** — unify launch zoom, drawer slide, control-bar fade via theme tokens.
