# TwoFold

Read and listen to your own books, and always return to the same page and minute.

An Android reader for EPUB and PDF with a built-in audiobook player. No account, no ads. It uses the internet only when you ask it to: to find and download free books (Project Gutenberg, the Internet Archive, Wikisource, Unglue.it or your own OPDS catalogs) and to look up a book's details and covers on Open Library.

Tests: `flutter test`. Screens in three themes: `LOOK=1 flutter test test/look_test.dart --update-goldens` (PNGs in `build/look`). Store screenshots: `SHOTS=1 flutter test test/store_shots_test.dart --update-goldens`. Checks against the real sites: `LIVE=1 flutter test test/live_covers_test.dart`.

## Build

```
flutter test
flutter build appbundle --release
```

For a side-loaded APK, `flutter build apk --split-per-abi --release` gives one small APK per phone type. Debug and profile builds install as "TwoFold Dev" beside the Play version.

For Play uploads, create `android/key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. See `docs/release-guide.md`.
