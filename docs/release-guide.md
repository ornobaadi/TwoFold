# Releasing TwoFold on Google Play

Play Console's rules change; where a screen differs from this guide, follow the screen.

## 1. Before anything

Check the app on your phone, including lock screen audio, notification controls, and resuming after force-closing. Search Play for "TwoFold" and do a trademark search.

## 2. Create the upload key (once)

Run from the project folder:

```
keytool -genkey -v -keystore android/upload-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties`:

```
storeFile=../upload-key.jks
storePassword=YOUR_PASSWORD
keyAlias=upload
keyPassword=YOUR_PASSWORD
```

Back up the key file and passwords outside this PC. Never commit them. Both are already in `.gitignore`.

## 3. Build the upload file

```
flutter clean
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Every later upload needs a higher number after the `+` in `pubspec.yaml` (`0.1.0-beta+2`), and update `appVersion` in `settings_screen.dart` when the first part changes.

## 4. Host the privacy policy

Upload `docs/privacy-policy.html` anywhere public that works without a login, such as GitHub Pages or Netlify Drop, and keep the link.

## 5. Create the app in Play Console

App name `TwoFold: Ebook & Audiobook`, type App, Free, default language English. Then complete **App content**:

| Form | Answer |
|---|---|
| Privacy policy | Your hosted link |
| Ads | No |
| App access | All functionality available without special access |
| Content rating | Reference/other app type; answer honestly. Note it opens files the user supplies and has no user interaction or sharing |
| Target audience | 18 and over is the simplest accurate choice; the app isn't designed for children |
| News / Health / Financial / Government | No / none |
| Data safety | Collects no data; shares no data. See below |
| Foreground service | Media playback. See below |

**Data safety:** "Does your app collect or share user data?" No. Google defines data handled only on the device as not collected, which is TwoFold's case. Check this against the wording shown and the policy link.

**Foreground service:** type `mediaPlayback`. Use: "Plays the user's audiobook with the screen off, controlled from the notification and lock screen." It's user-initiated and must continue in the background. If a video is requested, record: start a book, press play, lock the phone, show the notification controls.

## 6. Test tracks

1. **Internal testing:** upload the `.aab`, add your email, install through the link. Accept Play App Signing when offered.
2. **Closed testing:** new personal accounts have generally needed at least 12 testers opted in for 14 continuous days. Check the Dashboard for your account's current requirement.
3. **Apply for production** from the Dashboard once eligible, answering the questions about your test.

## 7. Release to production

Create the release with notes such as: "First release of TwoFold: read and listen to your own books, and always return to the same page and minute." Roll out, then check Pre-launch report and Android vitals for crashes.

## After launch

Ask friends who actually use it for honest reviews, reply to reviews, and update screenshots when the look changes.
