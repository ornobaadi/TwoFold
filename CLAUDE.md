# CLAUDE.md — TwoFold

Flutter (Android first) reader with a built-in audiobook player. Read the book, listen to the audio, and always resume at the same page and the same second.

## Source of truth (read before changing anything)

| File | What it decides |
|------|-----------------|
| `PRD.md` | Features F1–F10, key behaviours, success criteria. Scope questions end here. |
| `Architecture.md` | Packages, folder layout, SQL schema, audio flow, progress-saving triggers, gestures. |
| `design.md` | Colours, type, spacing, screens, things to avoid. |
| `phases.md` | Build order. Finish a phase before starting the next. |

If these files disagree, PRD wins on behaviour, design.md on looks, Architecture.md on structure. Record the conflict and the resolution under Decisions below.

## Rules that must not break

- Audio and page position are independent. Page turns never touch audio, audio never turns pages.
- Opening a book never autoplays. Land on restored page + restored time, paused.
- Progress is saved by column-scoped writes (see Decisions), on: every 5 s while playing, pause/stop, every page turn, `AppLifecycleState.paused/detached`.
- One `AudioHandler` for the whole app. Switching books saves the current one first.
- No network permission. No Google Fonts calls; Literata and Inter are bundled assets.
- Design: Material 3 Expressive per `design.md`: colour roles from `schemeFor`, labels kept on controls, 48 dp touch targets, only Literata + Inter.
- Player bar and reader must never steal each other's touches.

## Skills in `.agents/skills` and how to use them here

- `ui-taste` (`reference/new-work.md`, `polish.md`, `audit.md`): use for building each screen and for the final visual review of each phase. The iOS playbook is not needed until the iOS build.
- `ui-ux-pro-max`: touch targets, contrast, accessibility checks. Its suggestions yield to `design.md`.
- `frontend-design`, `design-taste-frontend`: web-oriented; take only the anti-generic-look principles.
- `material-3-expressive`: the design language of the app. Flutter has no Expressive widget set, so `app/theme.dart` and custom widgets carry it.
- `android-clean-architecture`: Kotlin-specific; only the layering idea carries over (UI → controller → repo, repo hides sqflite, no UI code in `data/` or `audio/`).
- `no-ai-slop`: use when writing README, store text, and in-app copy.
- `design-mobile-apps` (needs paid API key), `aso`, `seo-audit`, `brag`, `product-launch-video`, `video-edit*`: out of scope for now.

## Build plan

Follows `phases.md`. v1 = Phases 0–4.

0. **Setup:** pubspec packages, fonts, `app/theme.dart` with 3 themes, Android manifest (foreground service, media playback, wake lock, notifications; no internet), folder skeleton.
1. **Player that remembers:** `data/db.dart` + `book_repo.dart` (progress first), `audio_handler.dart`, `player_controller.dart`, temporary test screen. Verify: lock screen, kill app, resume same second.
2. **Library + import:** `importer.dart`, `library_screen`, `book_card`, attach audio, remove book.
3. **Reader:** EPUB (`flutter_epub_viewer`) and PDF (`pdfrx`), location save/restore, page indicator.
4. **2-in-1 screen:** floating `player_bar`, `mini_play_button`, tap-centre toggle, auto-hide 4 s, Listen mode.
5. **Comfort (v1.1):** auto-rewind, sleep timer, skip length, reader settings sheet, chapters.
6. **Polish:** empty states, DRM error, large M4B/PDF test, battery check, release APK (<30 MB).

Testing: unit tests for repo and skip/clamp-across-tracks logic, widget tests for gesture isolation, manual device checks for background audio and force-kill resume.

## Risks to check early

- Package versions: Flutter 3.47.5 / Dart ^3.13.4 are newer than the doc's assumptions. Confirm each package resolves (`flutter pub add`) and that `just_audio` still offers `ConcatenatingAudioSource` (newer versions may favour another playlist API).
- `flutter_epub_viewer` uses a WebView; check swipe pagination vs. the player-bar overlay on a real device.
- Pre-existing `ios/ macos/ linux/ windows/ web/` folders exist although v1 is Android only. Leave them; do not maintain them.

## Decisions

- **Playlist API:** `just_audio` 0.10 deprecates `ConcatenatingAudioSource`. Use `player.setAudioSources(list, initialIndex:, initialPosition:)`.
- **file_picker 13:** the API is static, `FilePicker.pickFiles(...)` returns a list (empty on cancel). `FilePicker.platform` from older docs no longer exists. Single file: `FilePicker.pickFile()`.
- **Progress writes touch disjoint columns:** `BookRepo.saveAudio` and `saveReading` each update only their own columns (insert-ignore, then update, in one transaction) instead of one `INSERT OR REPLACE` of the whole row. A page turn can't overwrite the audio position or the reverse. This refines Architecture.md "Saving progress".
- **Absolute timeline:** the audio handler exposes one position measured from the start of the first track. Notification, lock screen scrubber, UI scrubber and skips all use it; `lib/audio/timeline.dart` maps it to (track, offset).
- **Interruptions:** the player is created with `handleInterruptions: false`. `DuetAudioHandler` pauses on a call or another app's audio and on headphone unplug, ducks on transient duck events, and never resumes by itself (PRD section 6).
- **`just_audio` `play()` future** completes only when playback pauses, so the handler does not await it.
- **Gradle memory:** this machine has 8 GB RAM; keep `org.gradle.jvmargs` at `-Xmx2G`.
- **Builds:** the user builds and installs. Claude runs `flutter analyze` and `flutter test` only, and hands over the build command.
- **Notification permission:** `MainActivity` exposes channel `duet/permissions`; the app asks for `POST_NOTIFICATIONS` at launch on Android 13+.
- **File picking is native:** `MainActivity` channel `duet/files` opens the document picker filtered by MIME type (EPUB/PDF, or audio), opening wherever Android last was, plus a folder picker that lists audio in subfolders. `file_picker` is gone. Android's system picker can't hide folders; it greys out files of other types.
- **Audio is not copied (changes PRD F1):** tracks store persisted `content://` URIs and play from the original location, so importing is instant and uses no space. Moving or deleting the originals makes that audio unavailable, and the reader says so. Book files are still copied because the viewers need a real file. Older imports keep their copies until the book is removed.
- **Same-book reopen:** `loadBook` does nothing if that book is loaded, so returning to a playing book keeps it playing. PRD "never autoplays" still holds: nothing starts playback on open.
- **Resume into the book:** `open_book` in settings is set when the reader opens and cleared when it is left, so after a kill the app returns to the reader (PRD use case 3).
- **Native EPUB reader (replaces `flutter_epub_viewer`, which failed on the user's phone in both its loading modes):** `epub_book.dart` parses the zip and XHTML into blocks in an isolate, `epub_layout.dart` paginates with `TextPainter`, `epub_view.dart` shows them in a `PageView`. CSS is ignored on purpose. Location is `block:char`, stable across font changes. No WebView.
- **EPUB font:** book text is Literata, as design.md asks.
- **Primary buttons are ink, not accent:** design.md reserves the accent for play, progress and selection.
- **Isolates:** spawn from top-level functions only; a closure in a widget method can capture the widget and fail when sent.
- **PDF paging:** a `PageView` of `PdfPageView`s, not `PdfViewer`, for real one-page swipes. No `InteractiveViewer`: it competed with the swipe.
- **No `epubx`:** it pinned `image`/`archive` 3, which held `pdfrx_engine` at a version that does not compile on this Dart. `parseOpf` in `importer.dart` reads title, author and cover with `archive` and `xml`. This replaces the Architecture.md entry.
- **`pdfrx` pinned at 2.6.6:** 2.7+ compiles a C library in a build hook, which breaks `flutter test` on this PC (no desktop C compiler). Below about 2.4.6 does not compile on this Dart. pdfrx still downloads PDFium from GitHub at build time, so the build machine needs internet; the app does not.
- **Short interruptions resume (refines PRD section 6):** a transient focus loss outside a call resumes if it ends within 30 s; calls and other apps' music stay paused.
- **No speech-to-text search:** matching heard words needs a transcript. Offline transcription is too heavy for this app, so search is on the book text, then an estimate moves the audio.
- **Audio chapters:** Nero `chpl` atoms are parsed; QuickTime text-track chapters are not. Without chapters, each audio file is one chapter.
- **No DRM check:** personal app, at the user's request. A file is refused only if no text can be read from it.
- **Material 3 Expressive replaces the paperback look (user request, 2026-11-01):** `design.md` was rewritten. No dynamic colour: the page tint and brand stay predictable, and it would add a plugin.
- **Identity:** app TwoFold, package `com.ornobaadi.twofold`, Dart package `twofold`. A new application id installs as a new app, so nothing migrates from the old `com.example.duet` install.
- **Search no longer offers to move the audio:** the estimate was too rough beside an exact search hit. My places keeps its labelled "close, not exact" moves.
- **Bundled samples:** the app has no internet, so sample audio ships in the app and is copied to app storage on first launch.
- **Release signing:** `android/key.properties` (not committed) selects the upload key; without it, release builds use the debug key.

## Update log

Every change to the project gets a line here: date, what, why.

- 2026-11-02 — Search fixed (user report: results opened the wrong page). The search keyboard resized the reader behind it, re-paginating the book with a stale position, and the jump then used an unreliable controller. Reader no longer resizes for the keyboard; jumps use a fresh controller and keep their target through re-layouts. Added exact-line highlight in PDFs (char rects) and a result bar with next, previous, all results and close.
- 2026-11-02 — Added three bundled sample stories with LibriVox audio (`import/samples.dart`, `assets/samples`, about 8 MB): The Story of an Hour (caseyveronica), The Emperor's New Clothes (Phil Chenevert), The Lady, or the Tiger? (David Federman). Copied into the library on first launch; removed ones stay removed; Settings can restore them. EPUBs are built from public domain text with no Gutenberg branding; audio is mono 32 kbps MP3. Build bumped to `0.1.0-beta+2`.
- 2026-11-02 — Version set to 0.1.0-beta, build 1 (user request). Fixed Listen controls overflowing on 360 dp phones when a book has chapters.
- 2026-11-02 — Play release prep: explicit R8 and resource shrinking, native debug symbols, backups off (matches the privacy claim), predictive back, font licences registered, unused `cupertino_icons` and pre-release migrations removed. Added feature graphic, screenshots (`test/store_shots_test.dart`, `SHOTS=1`), privacy policy page, listing and `docs/release-guide.md`. Merged release manifest confirmed no INTERNET; `ACCESS_NETWORK_STATE` comes from a plugin and is disclosed.
- 2026-11-02 — Final logo: F (bookmark with play) in flat Midnight Coral: `#17173A` background, coral `#FF6B6B`/`#E84C5A` creased bookmark, `#FFE08A` play. Installed as launcher, themed, notification, splash and Play icons; masters in `docs/logo`, rejected concepts in `docs/logo-concepts`.
- 2026-11-02 — User disliked permanent orange. Added 11 colour palettes independent of the background (`AppPalette`, Blueberry default), bubble touch effect and spring squish (`app/bubbly.dart`), wavy progress on the Continue card, varied plain covers, new app icon (book with headphones, themed icon on Android 13+).
- 2026-11-01 — Renamed to TwoFold (`com.ornobaadi.twofold`) everywhere, new icon, notification icon, Play icon, upload-key signing, privacy policy, store text. Redesigned in Material 3 Expressive: new theme, library with Continue card, search and sort, add-book button, Edit book + Remove sheet, redesigned reader toolbar and player, Listen, Search, Edit, Settings screen. Added: Auto theme, font choice, keep screen on, custom cover, chapter next/previous, book position slider. Removed the search audio banner. `test/look_test.dart` lays out every screen in three themes; `LOOK=1` writes PNGs to `build/look`.
- 2026-11-01 — Notification sounds no longer pause audio (speech preset's `androidWillPauseWhenDucked` removed); short non-call pauses resume by themselves. Added: replace recording keeping the story position, book search with highlight, estimated page/audio matching (`sync_map.dart`) that improves with user-confirmed spots, My places (DB v3 `marks`), labelled tool row, visible book options, first-time help card.
- 2026-11-01 — Real cause of overlapping and cut-off EPUB lines: drawn text inherited the theme's letter spacing, measured text did not. `blockStyle` now uses `inherit: false`; a test checks rendered rectangles on real pages. Sections open on a new page with a centred title. Scrubber: `ScrubGuard` refuses a first jump to another chapter or over 60 s, and a second touch within 5 s goes through; thumb holds at the target while seeking.
- 2026-11-01 — User confirmed reading and audio work. Fixed cut-off lines (paginator now stores each slice's exact top and pages draw at those positions; rounding had drifted). Player card redesigned with chapter line and chapter marks on the scrubber; footer gets mini back and play buttons. PDFs: margins auto-cropped from measured ink, fit to width, tinted to the theme including Night (`pdf_crop.dart`).
- 2026-11-01 — Found by test: `PdfDocumentViewBuilder.file` reloaded the document on every rebuild, so each touch or page turn blanked the PDF. `PdfPane` now opens the document once.
- 2026-10-31 — Fixed three bugs from user screenshots: EPUB isolate closure captured the widget state, so loading failed; PDF zoom widget took swipes and taps (now raw-touch handling in `page_surface.dart` and `pdf_view.dart`); reader footer collapsed to label width. Controls now show on open. `test/reader_flow_test.dart` drives the real panes with Alice in Wonderland (Gutenberg) and real PDFs. Audio, notification and lock screen remain device-only checks.
- 2026-10-31 — User's phone showed the viewer failing in both modes. Replaced it with a native EPUB reader, removed the DRM check, stopped forcing picker start folders. Tested with generated EPUBs; not yet run on a device.
- 2026-10-31 — User report: EPUB reader loaded forever on a release build, picker showed all files, 300 MB+ app data. Added shrink rules, two-mode EPUB loading with a time limit, opening screen, controls reachable by footer tap, filtered native file and folder pickers, audio played in place (DB v2 adds `audio_tracks.title`), removal of the old picker cache at startup. Cause of the hang is inferred from source, not confirmed on a device.
- 2026-10-31 — Phases 2–6 (code, not device-tested): fixed the likely cause of the missing media notification (permission never requested) and added book cover art to it. Added the import screen (book + many audio files at once, natural sort, drag to reorder, add/remove later), library grid, continue bar, EPUB and PDF reader with saved location and contents, floating player, mini play button, tap zones, auto-hide, Listen mode, settings sheet, speed sheet, sleep timer, auto-rewind, skip length, three themes applied app-wide, audio chapters, first-launch hint, error states, adaptive icon and splash colour. Removed `dev_player_screen.dart`; startup deletes its old `scratch` book. Added `archive` and `image` dependencies.
- 2026-10-31 — Phase 1 verified by the user on a phone: locked-screen playback and resume after force-kill work. Notification controls did not appear.
- 2026-10-31 — Phase 0 (code): added packages (just_audio 0.10, audio_service 0.18, audio_session, flutter_epub_viewer 2.2, pdfrx 2.4, file_picker 13, sqflite, flutter_riverpod 3, path_provider, epubx, path, uuid). Android manifest: foreground service, media playback, wake lock, notifications, AudioService + MediaButtonReceiver; no INTERNET. `MainActivity` now extends `AudioServiceActivity`. Added `lib/app/theme.dart` (3 themes, tokens, 4 dp grid), folder skeleton, placeholder `main.dart`, boot test. `flutter analyze` clean, test passes. Debug APK build in progress. **Open:** Literata and Inter font files are not in `assets/fonts/` yet and are not declared in `pubspec.yaml` (declaring missing files breaks the build), so text falls back to the system font.
- 2026-10-31 — Phase 1 (code): added `data/models.dart`, `db.dart` (books, audio_tracks, progress, settings), `book_repo.dart`; `audio/timeline.dart`, `audio_handler.dart` (just_audio + audio_service: absolute timeline, skip across tracks, speed 0.75–2.0 in 0.05 steps, 5 s save timer, save on pause/stop/seek/speed, interruption handling, headset next/previous = skip), `player_controller.dart` (providers + `ProgressLifecycleGuard` saving on paused/detached); `app/format.dart`; temporary `features/player/dev_player_screen.dart` (pick audio, play, scrub, skip, speed); `main.dart` now boots the DB and `AudioService`. Dev dependency `sqflite_common_ffi` for repo tests. 16 tests pass (timeline, formatTime, repo, app shell). **Not yet verified on a device:** lock screen, headset, kill and resume.
- 2026-10-31 — Build fix: the Gradle JVM crashed (out of memory) because `android/gradle.properties` asked for `-Xmx8G` on an 8 GB machine with ~2 GB free. Lowered to `-Xmx2G`, metaspace 1G, code cache 256m, and set a 10 min daemon idle timeout. Stopped stale daemons. Rebuild running. Keep builds sequential on this machine; do not run two Gradle builds at once.
- 2026-10-31 — Fonts: downloaded `Inter.ttf` and `Literata.ttf` (variable fonts, OFL, from google/fonts on GitHub) into `assets/fonts/` and declared them in `pubspec.yaml`. First debug APK build failed with exit 4 (cause being investigated); rerun in progress.
- 2026-10-31 — Read PRD, Architecture, design, phases and all skill entry points. Created this file with the build plan. No code written yet; project is still the Flutter counter template.
