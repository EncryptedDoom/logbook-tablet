# Visitors Book

The 7th Battalion visitors book: a Flutter app for an Android tablet
(Samsung Galaxy Tab S7). Visitors handwrite their name, place, comment,
appointment and signature with the stylus and pick the date from a calendar.
Name and place are read with on-device ML Kit handwriting recognition so the
book can be searched. Records can be exported, printed, or saved as a PDF.

Everything stays on the device: SQLite for storage, no server, no sharing.

## Set up (macOS or Windows)

1. Install [Flutter](https://docs.flutter.dev/get-started/install) and
   [Android Studio](https://developer.android.com/studio).
2. Run `flutter doctor` and fix anything it flags under Android. Accept the
   Android licences when it asks (`flutter doctor --android-licenses`).
3. In Android Studio's Device Manager, create a **Pixel Tablet** on
   **Android 13 (API 33)** and start it.
4. From this folder:

   ```sh
   flutter pub get
   flutter run --dart-define=ALLOW_FINGER_DRAWING=true
   ```

The emulator needs internet the first time the app opens, to fetch the
handwriting model.

### Test mode

`ALLOW_FINGER_DRAWING=true` lets a mouse or finger draw, since an emulator has
no stylus. Such builds show a red **TEST MODE** ribbon. Never install one on
the real tablet: it turns off palm rejection. Builds for the tablet use plain
`flutter run` / `flutter build apk`.

## Activation

The app opens to a lock screen until the device is activated, so a copied APK
is useless on an unapproved tablet. (Android no longer lets apps read the MAC
address; activation binds to `ANDROID_ID` instead.)

1. The lock screen shows a 12-character device code.
2. The administrator signs it on their PC:
   `dart run tool/activate.dart <DEVICE-CODE>`. This opens a page with an
   activation QR and the code as text.
3. Scan the QR on the device, or paste the code under *Type the code instead*
   (always the case on an emulator).

Only the administrator holds the private key, in `%USERPROFILE%\.logbook`,
outside this repository. `lib/activation_key.dart` is the public half and is
safe to commit. Never commit or send the private key.

The device code depends on the signing key as well as the device, so an app
you build yourself shows a different code from an APK built on another
machine. Each needs its own activation. To see the lock screen again on an
emulator:

```sh
adb shell run-as com.logbook.logbook rm databases/activation
```

## Tests

```sh
flutter analyze
flutter test
```

## Layout

| Path | What |
| --- | --- |
| `lib/main.dart` | App entry, activation gate, cover screen |
| `lib/entry_screen.dart` | Search, recent entries, the entry form |
| `lib/handwriting_pad.dart` | Stylus-only writing pad; strokes for recognition, PNG for the record |
| `lib/date_field.dart` | Calendar date picker |
| `lib/recogniser.dart` | ML Kit digital ink recognition |
| `lib/search.dart` | Fuzzy name/place search, exact date matching |
| `lib/database.dart` | SQLite schema and migrations (`logbook_raw`, `logbook_refined`) |
| `lib/record_view.dart` | One record in full |
| `lib/export_screen.dart`, `lib/export_pdf.dart` | VIP choice, paper size, print, save as PDF |
| `lib/activation_*.dart`, `lib/licence.dart` | Device activation |
| `tool/activate.dart` | Administrator's tool to issue activation codes |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Native device ID and "Save as" |

Database changes go through a new schema version and a step in `_upgrade` in
`lib/database.dart`; the real tablet holds records that must survive updates.
