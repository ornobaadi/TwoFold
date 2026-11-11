# Play Store listing

Paste these into **Grow users > Store presence > Main store listing**.

**App name (30 max):** TwoFold: Ebook & Audiobook

**Short description (80 max):** Read and listen to your books, and find free classics. Never lose your place.

**Full description:**

Your ebook and your audiobook, in one app.

Read a few pages at home, listen on the way to work, and carry on. TwoFold remembers your page and your minute on its own, so you always come back to where you were.

READ
• EPUB and PDF reader with one-page swipes
• Search inside the book, with recent searches and every match highlighted
• Save places and name them, then jump back to the page and the audio
• Text size, font and line spacing you can change
• PDF margins trimmed so pages fill the screen

LISTEN
• Audiobook player for MP3, M4B, M4A, AAC, OGG, OPUS, FLAC and WAV
• Add one file or a whole folder, then drag parts into order
• Chapters, speed from 0.75× to 2×, skip buttons and a sleep timer
• Lock screen, notification and headset controls
• What's playing stays one tap away at the bottom of the home screen

FREE AUDIOBOOKS
• Free LibriVox recordings, matched to the book you got
• Search and browse LibriVox by title or author, filter by length
• Plays straight away and saves itself for offline, on Wi-Fi

FIND FREE BOOKS
• Search and browse Project Gutenberg, the Internet Archive, Wikisource and Unglue.it
• Popular, latest and random lists, or add any OPDS catalog by its link
• Ratings, descriptions and subjects from Open Library, kept with the book
• Real covers: pick from the covers of other editions, or use a picture from your phone

MAKE IT YOURS
• Paper, Sepia and Night backgrounds, or follow the phone
• Five quiet accent colours
• Switch to another narrator's recording at about the same place in the story

PRIVATE BY DESIGN
No account. No ads. No tracking. TwoFold uses the internet only when you look for free books, details or covers, and your library stays on your phone.

One free public domain story with audio is included, so you can try it the moment you install. TwoFold does not sell books, and it can't open DRM-protected files.

## Assets (in `docs/store`)

| Slot | File |
|---|---|
| App icon, 512 x 512 | `docs/logo/twofold-icon-512.png` |
| Feature graphic, 1024 x 500 | `docs/store/mockups/feature-graphic.png` |
| Phone screenshots, 1440 x 2560 (9:16), in that order | `docs/store/mockups/screenshot-1...7.png`: together, reader, player, free classics, about the book, places, night |
| Plain screenshots (spare) | `docs/store/screenshot-1...7.png` |

Mockups are made by `python tool/store_mockups.py` from `build/mock` (`SHOTS=1 SHOT_SIZE=1220x2712 flutter test test/store_shots_test.dart --update-goldens`, then copy `build/shots/*.png` to `build/mock/`) and phone captures in `assets/screenshots`. Book covers in the shots are public domain first editions in `docs/store/covers` (sources and licences in its `CREDITS.md`). Store images show only public domain or openly licensed books: Play rejects other people's covers and titles, and they would suggest TwoFold sells them.

## Search terms the listing targets

ebook reader, audiobook player, epub reader, pdf reader, read and listen, m4b player. Play has no keyword field, so these are worked into the title and description. Don't add competitor names or phrases like "best".

## Store settings

- **Category:** Books & Reference. **Tags:** choose the closest reader and audiobook tags offered.
- **Contact email:** ornobaadi.dev@gmail.com
- **Price:** Free. A paid app can't later be made free in reverse, and free can't later become paid, so decide before publishing.

## Release notes for 0.3.0 (build 5)

Paste into **Release > What's new in this release** (500 characters max; this is 464):

```
• Free audiobooks: classics come with a LibriVox recording
• Get the book and its audiobook in one tap
• Plays straight away, downloads for offline on Wi-Fi
• One search for Gutenberg, LibriVox and the Internet Archive
• Real covers, and lists to browse: Mystery, Romance and more
• Filter by length, one reader, or not yet on your shelf
• Read | Listen switch at the top of every book
• Shelf filters: With audio, Downloaded
• A new welcome for first-time readers
```

## Release notes for 0.2.0 (build 4)

Paste into **Release > What's new in this release** (500 characters max; this is 451):

```
• Find free books: Project Gutenberg, Internet Archive, Wikisource and Unglue.it
• Real covers: pick from other editions, or use a photo
• About this book: ratings, description and subjects
• New paper-and-ink look, with Shelf, Find and Settings in a bottom bar
• What's playing stays one tap away
• Scrub freely: a "Back to" button undoes a long jump
• Name your saved places; recent searches in books
• Smaller app: one sample story instead of three
```
