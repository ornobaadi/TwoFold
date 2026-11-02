# TwoFold

Read and listen to your own books, and always return to the same page and minute.

An Android reader for EPUB and PDF with a built-in audiobook player. No account, no ads, no internet access.

## Build

```
flutter test
flutter build appbundle --release
```

For Play uploads, create `android/key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. See `docs/release-guide.md`.
