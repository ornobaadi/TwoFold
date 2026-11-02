# Design

**Idea:** Material 3 Expressive around a quiet page. The chrome is bold, round and warm; the book itself stays plain.

## Rules

1. **One hero per screen:** the Continue card, or the play button.
2. **Keep labels** on controls. Clean never means guessing.
3. **Shape shows state:** play is round when paused and squared while playing; buttons square up when pressed; the chosen theme swatch rounds out.
4. **Colour comes from roles** (`schemeFor` in `app/theme.dart`), seeded from the chosen `AppPalette`. Primary for the main action, containers for emphasis. Never hard-code a hue.
5. **48 dp minimum** touch targets. Honour the system's reduced-motion setting.
6. **The page is sacred:** controls hide while reading and never catch a page swipe.
7. **Don't add it unless it earns its place.** No badges, streaks or onboarding carousels.

## Foundations

- **Colour:** eleven palettes, Blueberry by default.
- **Background:** Auto (follows the system), Paper, Sepia, Night. Any colour works with any background.
- **Touch:** `BubbleSplashFactory` on every ink surface; `Bubbly` squish and spring on primary controls and cards.
- **Type:** Literata for titles and book text, Inter for UI. Inter is an optional reading font.
- **Shape:** cards and sheets 28 dp, tiles 16 dp, buttons fully round.
- **Motion:** spatial changes use `springCurve` over 280 ms; pages rise and fade over 300 ms.

## Screens

- **Library:** title and settings; Continue card; search and sort; 3-column grid; Add book button. The cover's options offer Edit book and Remove from library.
- **Add / Edit book:** cover, title, author, then ordered audio. One button at the bottom saves.
- **Reader:** page only. Tap the middle for the top bar with a position slider, the player card and the labelled toolbar (Contents, Search, My places, Text, Listen).
- **Listen:** big cover, scrubber, big controls, then Speed, Sleep and Chapters.
- **Settings:** appearance, reading, listening, about.
