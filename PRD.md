# PRD — TwoFold (working name)

A reader with an audiobook player built in. Read and listen at the same time, or just listen. The app always remembers where you were in both.

## 1. Problem

When I read along with an audiobook, I deal with two separate things: a book (paper, or one app) and an audio player (another app). Switching between them is clumsy. Keeping track of "page 33 / 15:00" is manual. When I lose focus for a moment, rewinding a few seconds takes too many taps.

## 2. Goal

One app, one screen. The book fills the screen, and small audio controls float on top. Swipe to turn pages, tap to rewind 5 seconds. Close the app at any moment and come back to exactly the same page and the same second.

## 3. Users

- **Primary:** me. I read and listen to books I bought (DRM-free EPUB/PDF + MP3/M4B) on an Android phone.
- **Secondary:** anyone who reads along with audiobooks, or uses audio to stay focused while reading.

## 4. Core use cases

1. **Read + listen.** Open a book. Audio plays while I swipe through pages. I tap ⏪ when I miss something.
2. **Just listen.** Switch to Listen mode, lock the phone, and keep listening from the lock screen or earbuds.
3. **Resume.** Pause, switch apps, or kill the app. Next time, I'm back on the same page and at the same audio time.
4. **Import.** Add a book file and attach its audio files once.

## 5. Features

### Must have (v1)

| # | Feature | Detail |
|---|---------|--------|
| F1 | Import book | EPUB and PDF from the device's file picker. Copied into app storage. |
| F2 | Attach audio | One or more audio files (MP3, M4A, M4B) per book, played in order as one timeline. |
| F3 | Library | A grid of books showing cover, title, and progress for page and audio. |
| F4 | Reader | Full screen. Swipe left/right to turn pages. EPUB reflows to the screen size, PDF shows fixed pages. |
| F5 | Floating player | ⏪ 5s · ▶/⏸ · ⏩ 5s · current time. Tap the page to show or hide it. |
| F6 | Listen mode | A full-screen player without the text: cover, chapter, big controls, scrubber. |
| F7 | Background playback | Keeps playing with the screen locked or the app in the background. Lock screen and notification controls. |
| F8 | Headset controls | Play/pause, plus next/previous mapped to skip ⏩/⏪. |
| F9 | Auto save & resume | Saves page and audio position on pause, on leaving the app, and every 5 seconds while playing. Restores both when the book opens. |
| F10 | Speed | 0.75× – 2.0× in 0.05 steps, saved per book. |

### Should have (v1.1)

- **Auto-rewind on resume:** after a pause of more than 60 seconds, go back 3 seconds before playing again.
- **Sleep timer:** 15 / 30 / 60 minutes, or end of chapter.
- **Skip length setting:** 5 / 10 / 15 / 30 seconds.
- **Reader settings:** font size, line height, and theme (Paper / Sepia / Night).
- **Chapter list** for both the book and the audio, if the M4B has chapters.

### Could have (later)

- Manual sync markers ("page 33 = 15:00") so the app can offer to jump the audio when you jump pages.
- Bookmarks with a short note.
- Listening stats.

### Out of scope

- DRM-protected files (Audible, Kindle). The app only accepts plain files.
- Cloud sync, accounts, a store.
- Automatic text–audio alignment (AI).
- Text-to-speech.

## 6. Key behaviours

- **Audio and pages are independent.** Turning a page never changes the audio, and the audio never turns pages.
- **Opening a book never autoplays.** You land on the restored page with the audio paused at the restored time. One tap resumes.
- **Interruptions:** a phone call or another app's audio pauses playback. Unplugging headphones pauses it too. Playback does not resume on its own after a call.
- **One book plays at a time.** Opening another book pauses and saves the current one.
- **Missing audio:** a book without audio works as a plain reader, and the player bar shows "Add audio".

## 7. Success criteria

- Resume restores the right page and audio within 1 second of where it left off, 100% of the time (including after a force-kill).
- 5s rewind responds in under 100 ms.
- The page swipe never triggers a player button, and the reverse.
- Cold start to the last book in under 1.5 s on a mid-range phone.
- APK under 30 MB.

## 8. Constraints

- Flutter, Android first. iOS later should cost little, because the libraries are cross-platform.
- Fully offline. No network permission needed.
- Files stay on the device.
