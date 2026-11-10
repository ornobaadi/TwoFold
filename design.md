# Design

**Idea:** Folio. The app looks like a well-made book: paper and ink, a serif that leads, thin rules instead of coloured boxes, and one quiet accent colour. Nothing bounces, nothing shouts; the book is the colourful thing.

## Rules

1. **One hero per screen:** the featured book on the library, or the play button.
2. **Keep labels** on controls. Clean never means guessing.
3. **Ink for actions, accent for listening and progress:** the main button is ink on paper (`onSurface`); the chosen colour marks play, progress, links and the current choice. No tinted containers behind ordinary content.
4. **Colour comes from roles** (`schemeFor` in `app/theme.dart`), seeded from the chosen `AppPalette`. Covers without a picture use book-cloth colours (`bookCloth`), the same in every theme. Never hard-code a hue in a screen.
5. **48 dp minimum** touch targets. Honour the system's reduced-motion setting.
6. **The page is sacred:** controls hide while reading and never catch a page swipe.
7. **Don't add it unless it earns its place.** No badges, streaks or onboarding carousels.

## Foundations

- **Colour:** five accents (Indigo default, Forest, Clay, Plum, Ink), chosen in Settings as small dots. Container roles are neutralised in `schemeFor`, so no screen gets a tinted fill.
- **Fields:** outlined, filled with the lightest surface, so they show on dialogs and sheets.
- **Settings:** small-caps section labels over hairline cards; Look holds Background (four page previews, Auto split day and night) and Accent; segmented choices and switches are ink.
- **Background:** Auto (follows the system), Paper, Sepia, Night. Any colour works with any background.
- **Touch:** the standard ripple; `Pressable` settles a control back by at most 4% while held, with no bounce.
- **Type:** Literata for titles, list headings and book text (`titleMedium` is serif); Inter for small UI text. Inter is an optional reading font.
- **Shape:** buttons, fields and tiles 12 dp; cards 16 dp with a 1 dp hairline (`outlineVariant`), no fill colour; sheets and dialogs 20 dp; covers 8 dp. Play is a plain circle.
- **Lines:** progress is a straight 3 dp line (`ProgressLine`); sliders use the thin classic track; lists are separated by hairlines.
- **Motion:** `easeCurve` (ease-out cubic) over 220 ms; never an overshoot.
- **Size (compact, user request 2026-11-10):** body 15/13, list titles 15 serif, screen titles 19-22, the home hero title 22; buttons 44 dp tall (40 for outlined), search fields 44, the Add book button 48. Touch areas stay at least 48 dp through padding. The library grid is about 80 dp per column (four on most phones). Covers narrower than 64 dp show the title's first letter instead of words.

## Screens

- **Home dock:** Shelf, Find and Settings in a bottom dock: hairline top rule on the page colour, icon plus label always shown, the chosen tab in ink and bold with a short ink rule under it (no tinted pill). Above the dock, while a book's audio is loaded, a now-playing strip: small cover, title, time left, thin progress line, back-skip and play. Tapping the strip opens Listen. Tabs keep their state; back from Find or Settings returns to the shelf. The dock never shows in the reader or Listen.
- **Library:** title; the featured book ("Tonight's read", by time of day, or "Start here" before any book is opened): label, large Literata title, author, tilted cover, read percent and audio left, progress line, Keep reading (ink) and Listen (primary); then "On your shelf" with search, sort, 3-column grid on every phone (more only from 600 dp); Add book button. The cover's options offer Edit book and Remove from library.
- **Add / Edit book:** cover, title, author, then ordered audio. One button at the bottom saves.
- **Reader:** page only. Tap the middle for the top bar with a position slider (while dragging it says "Go to 42% of the book"; after a jump a "Back to Page 33" button shows for 10 s), the player card and the labelled toolbar (Contents, Search, My places, Text, Listen).
- **Scrubbing audio:** a drag always goes where it is let go. A jump of 30 s or more shows "Back to 12:40" under the scrubber for 8 s; while dragging, the chapter under the thumb is named.
- **My places:** a "You are here" card (page and audio time) with an ink Save; saved places as rows (name or page, then page, audio time, "2 days ago"), a menu to name or remove one, Undo after removing.
- **Search in a book:** search field with clear; before typing, a short hint and recent searches as chips; results are hairline rows with page, a small where-in-book bar and percent, and the line with the match in bold on a light accent wash.
- **About this book:** cover (tap to change), title, author, rating, percent read and progress line; Keep reading (ink) and Listen; facts card (from, first published, pages, format, audio, added); About with Read more; subjects; the Open Library note. Books from Find arrive with these. For the user's own files a card offers "Look up details", which sends only the title and author. Opened from the book options, a long-press on the home cover, or the book title in the reader.
- **Choose a cover:** a tall sheet: the current cover, "From phone", then a 3-column grid of covers of other editions from Open Library, each labelled with year and publisher; plain tiles while loading; a spinner on the tile being saved; the note that covers belong to their publishers.
- **Listen:** big cover, scrubber, big controls, then Speed, Sleep and Chapters.
- **Settings:** appearance, reading, listening, about.
- **Find free books:** search field for the chosen library; libraries as chips (Project Gutenberg, Internet Archive, Wikisource, then the user's own catalogs and "Add catalog"); BROWSE lists in one hairline card (Gutenberg: Popular, Latest, Random; the Archive: Most downloaded, Recently added; a catalog: its own sections). Results are rows: book-cloth cover drawn from the title, serif title, author, and Get / Open. A row opens the details sheet: cover (Open Library's when it has one), title, author, star rating with count and "want to read", one Get book button that turns into a progress bar with MB and percent, a facts table (first published, pages, format, source), About (six lines, Read more), Subjects, and a line saying the details come from Open Library. Browsing stays plain: details load only when a book is opened. Downloads show in a tray at the bottom with cover, title, author, progress and Open or Retry. Long-press a catalog chip to remove it.
