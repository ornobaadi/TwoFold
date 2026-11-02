# Phases

Every phase ends with something I can use on my phone. Do them in order; don't start the next one until the current one feels solid.

---

## Phase 0 — Setup (½ day)

- `flutter create duet`, Android only for now.
- Add packages (see Architecture.md).
- Folder structure, theme file with the colours and fonts from design.md.
- Android: foreground service + media permissions in the manifest.

**Done when:** an empty app runs on the phone with the right fonts and colours.

---

## Phase 1 — Player that remembers (2–3 days)

The most important part first, even before there's a reader.

- Pick audio files → play them as one timeline (`ConcatenatingAudioSource`).
- Controls: ⏪ 5s, play/pause, ⏩ 5s, scrubber, speed.
- Background playback + lock screen + notification controls (`audio_service`).
- Headset buttons.
- Interruption handling (calls, unplugged headphones) via `audio_session`.
- Save position every 5 s, on pause, on app background. Restore on launch.

**Done when:** I can listen with the screen locked, kill the app, reopen it, and continue from the same second.

---

## Phase 2 — Library + import (1–2 days)

- Import EPUB/PDF, copy into app storage, extract title/author/cover.
- Attach audio to a book.
- Library grid with progress.
- Remove a book (deletes its copied files).

**Done when:** I can add 3 books with their audio and see them in the library.

---

## Phase 3 — Reader (3–4 days)

- EPUB: paginated, swipe left/right, reflows to the screen.
- PDF: one page per screen, swipe left/right, pinch zoom.
- Save position (EPUB location / PDF page number) on every page turn. Restore on open.
- Page indicator ("33 / 412" or "Ch 4 · 38%").

**Done when:** I can read a book, close it, reopen it on the same page.

---

## Phase 4 — 2-in-1 screen (2–3 days)

- Floating player bar on top of the reader.
- Tap the centre of the page → show/hide the bar and the top bar.
- Mini play button stays visible when the bar is hidden.
- Make sure swipes and button taps never interfere.
- Switch between Read and Listen mode.
- Listen mode screen.

**Done when:** I read a full chapter while listening, using only swipes and the floating bar, then lock the phone and keep listening.

---

## Phase 5 — Comfort (2–3 days) → v1.1

- Auto-rewind on resume after a long pause.
- Sleep timer.
- Skip length setting.
- Reader settings: font size, line height, Paper / Sepia / Night.
- Chapter lists.

---

## Phase 6 — Polish & release to myself (1–2 days)

- Empty states, error messages ("This file is DRM-protected and can't be opened").
- Test with a large M4B (10+ hours) and a 500-page PDF.
- Battery check: an hour of locked playback.
- Build a release APK and install it.

---

## Later

- Sync markers between page and audio time.
- Bookmarks with notes.
- iOS build.

**Total for v1 (Phases 0–4): about 2 weeks** of evenings and weekends.
