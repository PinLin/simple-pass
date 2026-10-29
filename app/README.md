# SimplePASS app

The Flutter Android app itself. See the [top-level README](../README.md)
for project context.

## What it does

1. Profile list: one row per MobilePASS profile showing its current 6- or
   8-digit passcode. Tap a row to copy the passcode; with the profile's
   "Append PIN when copying" on, the PIN followed by the passcode is copied.
   Event-based rows show the counter, and their ✓ button marks the passcode
   as used (advances the counter, shows an Undo snackbar that puts it back).
   The › button at the right of each row opens its edit page; long-pressing a row starts selection mode (below).
   Time-based rows update every second
   and show a countdown in place of the ✓; they have no counter.
   Challenge-response rows show dots and a keypad icon; tapping one opens a
   dialog that takes the Challenge Code (exactly 6 or 8 digits, per the
   Policy String). After OK the row shows just the passcode and a ✓;
   tapping the row copies it like
   any other, and ✓ puts the row back to waiting. The entered challenge is
   only kept in memory: relocking, editing or deleting the profile, or
   restarting the app, clears it. They have no counter either. TOTP rows
   look like time-based ones and HOTP rows like event-based ones; both show
   just the name. The + button adds a profile, first asking which kind:
   "MobilePASS – Manual enrollment" (Activation Code), "MobilePASS – Auto
   enrollment" (Enrollment String) or "Add manually" (standard TOTP/HOTP); add
   pages are titled after the kind. In selection mode (a
   Set of ids; on while it isn't empty) codes are masked, the row buttons and
   + are hidden, selected rows take the secondary container color, and the
   app bar shows ✕, "N selected" and a trash button. Tapping a row toggles
   it; ✕, Back or deselecting the last row ends the mode. Delete confirms with
   the count and removes the selection in one write. The list is a
   `ReorderableListView` with `ReorderableDelayedDragStartListener` rows, so a
   long press then drag moves that one row (saved right away through
   `ProfileStore.reorder`) while a plain drag scrolls.
2. Edit page: name, Policy String (optional) and Activation Code (new
   profiles only), counter (event-based, existing profiles only; new ones
   start at 0), PIN (optional, 4–16 digits) and "Append PIN when copying".
   A new profile is prefilled
   with a randomly generated Activation Code (copy and regenerate buttons next
   to it); while untouched, it switches to the matching layout when a v2
   Policy String is entered. On save, Activation Codes must pass their check
   characters, Policy Strings must be valid and supported (v1/v2, event-based,
   time-based or challenge-response), and the Activation Code's layout must match the Policy String
   version. After creation the Activation Code and Policy String are no longer
   shown on the edit page; they move to the registration information sheet
   (copy buttons only) and are saved unchanged, so codes saved
   earlier keep working even if their check characters are wrong. An existing profile's edit page is
   titled by the kind of code it makes rather than how it was added:
   "TOTP profile", "HOTP profile" or "Challenge-response profile" (a
   time-based MobilePASS profile is a "TOTP profile"). A profile that uses the
   MobilePASS algorithm (MobilePASS manual or auto enrollment, or manual TOTP
   with "Use MobilePASS format") shows a non-clickable "MobilePASS format" line
   at the top; standard TOTP/HOTP has none. The secret key is a read-only field
   above the digits setting, hidden by default with eye and copy buttons
   (Base32 for standard OTP, the derived key in Base32 for MobilePASS), and the
   parameters (digits, algorithm, period, challenge length) are read-only grey fields.
   The overflow menu has up to three items: "MobilePASS registration info" (only
   MobilePASS manual or auto enrollments), which opens a scrollable sheet titled
   "MobilePASS – Manual enrollment" (Activation Code and Policy String) or
   "MobilePASS – Auto enrollment" (Enrollment String, serial number, Policy
   String), each with a copy button; "Copy otpauth link" (only where a link can
   be made: standard OTP and MobilePASS event-based), which copies it at once as
   sensitive data with auto-clear and shows "Link copied"; and Delete, which
   confirms the profile name and only removes the local profile. The page has no
   otpauth link field. Standard TOTP/HOTP links preserve algorithm,
   digits, period and issuer and use the current form name and counter. An empty
   Policy String shows as "Not set" in registration information. The editable PIN
   is local only; changing it does not update the PIN on the server. There is no
   Cancel button: going back
   (app bar, system button or gesture) with unsaved changes asks
   "Unsaved changes" with two choices, Discard and Keep editing; without
   changes it just goes back. The prefilled random
   Activation Code doesn't count as a change. On an existing profile
   "Append PIN when copying" saves as soon as it's switched (put back with
   a message if that fails), so it never counts as unsaved; on a new one it
   is saved with the rest. A registered but unsaved Enrollment String result
   asks the same question.
3. Enrollment String page: paste the Base64 Enrollment String
   (`EnrollmentURL`, `UserID`, `Passphrase`); a paste button reads the
   clipboard. The page shows which host it will register with and asks for
   the user ID or passphrase if the string leaves them out; the URL must be
   https. Register runs the DSKPP four-pass exchange (RFC 6063) with progress,
   asks for the OTP PIN when the server's policy wants one (it is sent to the
   server and saved as the profile's PIN), checks the server's key
   confirmation MAC and saves a profile holding the key itself. Network,
   HTTP, server-refusal, MAC and format errors are shown on the page and
   nothing is saved; if only the final save fails, Save retries it without
   registering again. A successful enrollment retains the original Enrollment String
   (including unrecognized vendor fields), URL, actual User ID and Passphrase,
   and original registration PIN. These are sealed with the key when the app lock
   is enabled, cleared from memory on lock and restored on unlock. The registration
   PIN remains unchanged when the local copy PIN is edited. Old profiles remain
   usable and explain that earlier enrollment inputs were not saved.
4. "Add manually" page: the Secret key field stays visible with one QR icon.
   It opens a bottom sheet offering the camera or a photo; selecting the camera
   requests camera permission, while choosing a photo uses the system picker.
   The QR icon is disabled while the chooser or an import is open. For a bare
   Base32 secret, users can choose TOTP or HOTP from a dropdown, 6 or 8
   digits, SHA-1/256/512 and a 1–3600 second period for TOTP; "Use MobilePASS
   format" (TOTP only) makes it a time-based MobilePASS secret (SHA-256, time
   steps counted from 2000 like MobilePASS, no export link). There is no
   starting counter field: a manual HOTP profile starts at counter 0, which
   can be changed on its edit page after adding. Defaults are
   TOTP/SHA-1/6 digits/30 seconds. A pasted or scanned otpauth URI supplies its own
   parameters, shown in the same fields but read-only until the link is replaced
   with a bare secret. Imported links are kept intact;
   customized manual parameters are stored as an otpauth URI, while default bare
   secrets keep their original text. A HOTP link's counter initializes the profile's
   own counter, which ✓ advances; the link text never changes. Issuer and
   account aren't stored apart from the link; with an empty name the link
   names the profile "issuer: account" as in Google Authenticator (or just
   the one that's present). A Secret that doesn't parse can't be saved. During
   import, invalid links get a specific message, including
   `otpauth-migration://` exports, which aren't supported, and Enrollment
   Strings, which point to "MobilePASS – Auto enrollment".
   Scanning asks for the camera permission at that moment (a denial shows an
   explanation, and "Open settings" once Android stops asking); photos come
   from the system Photo Picker and are decoded with ZXing, and the picker's
   cached copy is deleted afterwards. The credential is sealed like a registered
   key when protection is on. The overflow menu's "Copy otpauth link" copies the export link.
   The Base32 secret key is a read-only field on the edit page. Secrets are hidden on existing profiles and
   shown while adding, with sensitive, auto-cleared copying. New standard OTP
   input has no visibility toggle or dedicated paste action. The scanner uses the back camera, else any other; if none
   is found or none starts, it says so and suggests "From photo" or typing
   the secret.
5. App lock: "Require authentication to open the app" in Settings seals
   every profile's Activation Code, key or credential, PIN and saved enrollment inputs with an
   AndroidKeyStore key that Android only releases for 10 seconds after a
   strong biometric or screen-lock authentication. Turning it on warns that
   removing the screen lock later makes the profiles unrecoverable, then
   seals them all after one authentication; turning it off unseals them all,
   also after authenticating. New profiles follow the setting. While it's on
   (or anything is still sealed), a cold start and every return from the
   background show a lock screen (title, "SimplePASS is locked" and Unlock,
   nothing about the profiles) that asks for authentication once by itself;
   a canceled prompt stays there until Unlock is tapped. One authentication
   opens every sealed profile and seals any still in the clear (from the
   upgrade, or a write that failed), then shows the list; rows have no
   per-profile lock. The prompt's own pause doesn't relock. Going to the
   background drops the decrypted secrets and closes every page above the
   list, except an Enrollment String page with a registration running or a
   result not saved yet (the string is single use): that one stays, covered
   by the lock screen, and is back once the unlock succeeds. A sealed
   secret that doesn't decrypt (damaged, as opposed to a dead key) leaves
   that one profile without a code. If the setting is off but something is still sealed (a switch-off
   that didn't finish), the list asks for the unlock first and then shows a
   "Remove protection" banner. Switching the setting saves it first and puts
   it back if sealing or unsealing fails. Upgrading from per-profile
   protection: the first start turns the setting on if any profile was
   protected (otherwise it stays off, data untouched). Settings that can't be
   read count as on wherever a secret would otherwise be written in the
   clear (new profiles, the unlock's sealing). Only a successful prompt may
   pause the app without relocking it; relocking also clears snackbars, and
   a prompt canceled by leaving the app shows again on return. Settings is
   reachable only from the unlocked list, and coming back from it never
   unlocks by itself (only switching the lock on there, which authenticated,
   counts). Removing the phone's screen lock makes Android destroy the key,
   so sealed Activation Codes, keys and PINs are lost; when the lock screen
   then finds no credentials or a dead key, it offers to delete the sealed
   profiles, which also turns the lock off and leaves the others usable.
6. Settings, in this order: "Require authentication to open the app" (the
   app lock, default off); "Block screenshots" (default off; on sets
   `FLAG_SECURE`, blocking screenshots and hiding the app in recents; it is
   the stored `allowScreenshots` shown the other way round, so earlier
   choices keep their meaning); "Tap to reveal passcodes" (default off; on
   masks every code in the list with dots until its row is tapped, which
   shows and copies it; it is masked again when a time-based code changes
   (one tapped in its last 3 seconds stays shown through the next code too),
   after 30 seconds otherwise, and whenever the app goes to the background;
   Challenge Code responses show as soon as they're computed); clipboard
   auto-clear (never, 30 seconds, 1, 2 or 5 minutes; default 1 minute).
   Auto-clear is best-effort: a timer in the running app clears the clipboard
   only if it still holds what the app copied; if the app is in the
   background then, it clears on return, and if Android has closed the app
   by then, nothing clears it.
   While the app lock is on (or anything is sealed) the recents thumbnail is
   hidden: with `setRecentsScreenshotEnabled` on Android 13+, and with
   `FLAG_SECURE` on older versions whatever "Block screenshots" says, which
   the setting's subtitle then explains.

## Permissions

`INTERNET` (see below), `USE_BIOMETRIC` (protected profiles) and `CAMERA`.
`USE_FINGERPRINT`, which androidx.biometric declares for its
`FingerprintManager` fallback on Android 9 and older, is removed in the
manifest: with `minSdk` 30 that library only uses the platform
`BiometricPrompt` and `BiometricManager`.
The camera permission is requested through the
`me.pinlin.simple_pass/camera_permission` channel only when the user taps
"Scan QR code", never at startup; `android.hardware.camera` is declared
`required="false"`. Permissions the camera and image picker plugins would add
for video recording and file access (`RECORD_AUDIO`, `WRITE_EXTERNAL_STORAGE`,
the implied `READ_EXTERNAL_STORAGE`, `ACCESS_NETWORK_STATE`) are removed in
the manifest, as is the image picker's hint asking Google Play services to
install its backported photo picker. The Photo Picker needs no storage
permission; on Android 11–12 devices without one, Android shows its file
picker instead. Some devices open it in multi-select mode even for a single
photo, so picking may need a tap on Done.

## Network access

The app declares `INTERNET` for one purpose: Enrollment String registration,
which POSTs `application/dskpp+xml` messages to the https URL in the string
(`dart:io` `HttpClient`, no redirects). The server certificate must chain to
one of Android's system CAs: user-installed CAs aren't trusted, and no proxy
is used (neither the system proxy nor proxy environment variables); a
certificate failure gets its own error message. Nothing else connects; codes
are always generated offline.

The app includes FreeDroidWarn (woheller69/FreeDroidWarn), called from
`MainActivity`. On the first launch of each new version (a higher
`versionCode`) it shows a dialog about Android's developer verification
policy. It has no network code; its "Details" and "Solution" buttons only
open a web page in the browser when tapped. It is kept on purpose.

Besides the user ID and the authentication data, the messages carry the
device fields MobilePASS servers expect: OS type (Android), the Android
version (`Build.VERSION.RELEASE`, via the `me.pinlin.simple_pass/device`
channel), a "not rooted" flag (no root detection is done), and, when the
server asks for a device name, the profile name.

## Build / run

```bash
flutter pub get
flutter run --release        # connected Android device
flutter build apk --release  # produces build/app/outputs/flutter-apk/app-release.apk
flutter build apk --debug    # produces build/app/outputs/flutter-apk/app-debug.apk
```

Release builds (`flutter build apk --release`) sign with
`android/key.properties` (gitignored, with `storeFile`, `storePassword`,
`keyAlias`, `keyPassword`). Without it, any
release build fails with an explicit error instead of silently using the
debug key; debug builds and `flutter test` don't need it. See
`android/app/build.gradle.kts`.

Requirements: Dart 3.11.5+, Flutter 3.41.9+. Package id
`me.pinlin.simple_pass`. `minSdk` is 30 (Android 11): app-wide
protection needs `setUserAuthenticationParameters` and BiometricPrompt
accepting strong biometrics or the screen lock together.

## Tests

```bash
flutter test
```

Covers, with no mocking framework (in-memory fakes behind abstract
interfaces — `KeyValueBackend`/`Keystore` — plus `@visibleForTesting`
constructor injection):

- The HOTP/activation-code algorithm: known-answer vectors, 3000
  precomputed fixture vectors (`test/fixtures/mobilepass_vectors.json`),
  normalization and invalid-input handling; both activation code layouts and
  their check characters, policy-string parsing, the policy-dependent key,
  time-based and 8-digit codes and challenge-response codes.
- Enrollment String registration: string parsing, DSKPP key derivation and
  MACs checked against messages this project's test server recorded
  (`test/fixtures/dskpp_vectors.json`), RSA
  PKCS#1 v1.5, and the full exchange against an in-process test server
  (`test/fakes/fake_dskpp_server.dart`), including every error path.
- Standard tokens: RFC 4648 Base32 vectors, RFC 6238 appendix B vectors
  (SHA1/SHA256/SHA512, 6 and 8 digits), RFC 4226 appendix D, `otpauth://`
  parsing and its error cases, the TOTP/HOTP profile JSON (including older
  data without the new fields) and sealing of a protected TOTP secret.
- `ProfileStore`/`SettingsStore` JSON round-trips and validation
  (counter can't go negative, defaults).
- Widget tests: the profile list (copy, mark as used, undo, the › edit
  button, selection mode with delete and long-press-drag reordering versus
  plain-drag scrolling), the edit page, the TOTP add and edit pages (link import, scan
  and photo import via `FakeCameraPermission`/`FakeQrReader`, including a
  denied and a permanently denied camera permission), settings, and app-wide
  protection (including the migration from per-profile protection) via a `FakeKeystore` (enable/disable/cancel, prompt-then-retry,
  invalidated keys, secrets dropped in the background).
- Golden (screenshot) tests for the profile list (incl. time-based, 8-digit and challenge-response rows),
  the Challenge Code dialog, selection mode, edit/add pages, the add-kind sheet, the
  Enrollment String page, its OTP PIN prompt and a registered profile's edit page,
  the invalidated-keys dialog, the TOTP add page, a list with
  TOTP and HOTP profiles and the settings screen, in
  English and zh_Hant_TW, pinned to a Pixel 6 logical size (411x914).

## Layout

```
app/
├── pubspec.yaml
├── l10n.yaml                  # gen-l10n config (non-synthetic, output committed)
├── lib/
│   ├── main.dart
│   ├── mobilepass/             # pure-Dart HOTP/OCRA/activation-code/policy algorithm, DSKPP client
│   ├── otpauth/                # Base32, RFC 4226/6238 codes, otpauth:// parsing
│   ├── models/                 # Profile, Settings
│   ├── storage/                # KeyValueBackend + Profile/SettingsStore
│   ├── platform/                # ScreenGuard, Keystore, camera permission (MethodChannels), QR reader
│   ├── screens/                # profile list (incl. the lock screen), edit/add (incl. TOTP), QR scan, enrollment, settings
│   └── l10n/                   # app_en.arb, app_zh.arb + gen/
├── test/                        # unit + widget + golden tests
└── android/
    └── app/src/main/kotlin/me/pinlin/simple_pass/
        ├── MainActivity.kt       # FlutterFragmentActivity (BiometricPrompt needs it)
        ├── KeystorePlugin.kt     # auth-bound AES-GCM keys + BiometricPrompt
        ├── CameraPermissionPlugin.kt  # CAMERA runtime permission on demand
        ├── ClipboardPlugin.kt
        └── ScreenGuardPlugin.kt  # FLAG_SECURE, recents screenshot
```

## Known limitations

- **Android only** — no iOS target.
- **Golden tests only render the CJK characters in the test font
  subset** — `test/fonts/NotoSansTC-Subset.otf` covers the characters in
  the zh arb file; anything new renders as tofu until the subset is
  regenerated. A real device uses its system CJK font. To regenerate, with
  fontTools installed (`pip install fonttools`) and `NotoSansTC-Regular.otf`
  2.004 from notofonts/noto-cjk, run in `app/` (keeps every code point
  already in the subset and adds the zh strings):

  ```bash
  python3 -c "from fontTools.ttLib import TTFont; print(' '.join(f'U+{c:04X}' for c in TTFont('test/fonts/NotoSansTC-Subset.otf').getBestCmap()))" > keep.txt
  pyftsubset NotoSansTC-Regular.otf --unicodes-file=keep.txt --text-file=lib/l10n/app_zh.arb --output-file=test/fonts/NotoSansTC-Subset.otf
  ```
- **CJK text borrows a system font face** — on some devices (some Samsung
  phones) Flutter's text engine can't use the vendor CJK
  fonts listed in `fonts.xml` and every Chinese glyph falls through to the
  serif fallback. Only on devices that have Samsung's
  `/system/fonts/SECCJK-Regular.ttc`, and only with a CJK system locale
  (checked once at startup), the app copies the regular face for that region
  out of it (or, if that fails, out of `NotoSansCJK-Regular.ttc`) in the
  background and uses it as the text fallback. That costs about 14 MB of
  memory for as long as the app runs. Other devices load nothing, nothing is
  bundled, and if neither file is usable rendering stays as it was.
- **No cloud backup/sync** — Activation Codes and registered keys live only
  in this device's Keystore-backed secure storage. Losing the device loses
  the profiles; re-provision from your MobilePASS Activation Code, or ask
  your IT admin for a new Enrollment String, if that happens.
- **Enrollment String registration is tested against this project's own
  DSKPP test server only** — not yet against a production enrollment server.
- **Don't downgrade with registered or TOTP profiles** — an older version doesn't
  know these profile kinds and drops the fields it doesn't know
  when it saves, so those profiles' keys are lost and need a new
  Enrollment String (or the service's TOTP secret).
- **No Google Authenticator export import** — `otpauth-migration://` QR codes
  are refused; add each account from its own QR code or secret.
- **No starting counter when adding HOTP by hand** — a manual HOTP profile
  starts at counter 0; set the right counter on its edit page after adding.
- **Changing a registered profile's PIN is local** — it changes what is
  copied with the passcode, not the OTP PIN the server recorded.
- **No instrumented tests** — automated coverage is unit, widget and golden
  tests; on-device behaviour was checked by hand on one Android 16 phone.
