# SimplePASS

An unofficial Android OTP generator compatible with SafeNet MobilePASS
Activation Codes and Enrollment Strings. It generates event-based (HOTP),
time-based and challenge-response (Challenge Code) one-time passcodes entirely
on the device, with support for multiple profiles (tokens). It also holds
standard authenticator tokens (TOTP/HOTP, RFC 6238/4226, compatible with
FreeOTP and Google Authenticator) next to them.

The app works offline. The only network access is registering an Enrollment
String: SimplePASS then talks to the server that string names (https only),
once, to receive the profile's key. Nothing else ever connects anywhere.

Permissions: `INTERNET` (Enrollment String registration only), `USE_BIOMETRIC`
(protected profiles) and `CAMERA` (QR code scanning). The camera permission is
only requested when you tap "Scan QR code"; if you decline, you can still type
the secret in. Importing a QR code from a photo uses the system Photo Picker,
which needs no storage permission. QR codes are decoded on the device (ZXing);
the app includes no Google Play services, Firebase or ML Kit.

The app includes FreeDroidWarn (woheller69/FreeDroidWarn). On the first launch
of each new version it shows a dialog about Android's developer verification
policy. It makes no network connection; its "Details" and "Solution"
buttons only open a web page in your browser when tapped.

## What it does

- Three ways to add a profile: "MobilePASS – Manual enrollment" (Activation
  Code), "MobilePASS – Auto enrollment" (Enrollment String) and
  "Add manually" (a standard TOTP/HOTP token from a QR code or secret key).
- Add any number of profiles from a MobilePASS Activation Code
  (`XXXX2-XXXX2-XXXX2-XXXX2`), plus an optional PIN. A new profile starts
  with a freshly generated Activation Code, ready for self-enrollment on your
  company's portal; you can regenerate it, copy it, or paste one you were given.
  Activation Codes are checked (including their check characters) when saved.
  Once a profile is created, its Activation Code and Policy String move to
  the registration info sheet in the edit page's overflow menu, where they can
  be copied.
- Or add a profile from an Enrollment String your administrator sent. Paste
  it (or use "Paste from clipboard"); SimplePASS registers with the server it
  names using the DSKPP four-pass protocol (RFC 6063) and stores the key and
  Policy String the server returns. If the server asks for an OTP PIN, it is
  sent to the server and saved as the profile's PIN. A failed registration
  saves nothing.
- Or, with "Add manually", add a standard TOTP/HOTP profile for any service
  that works with FreeOTP or Google Authenticator: scan its QR code, import the QR code from a photo,
  or enter an `otpauth://` link or a Base32 secret (spaces, lowercase and missing padding are fine). The profile
  keeps the credential exactly as entered, the whole link or the bare secret,
  and uses everything the link specifies: algorithm (SHA1/SHA256/SHA512), 6 or
  8 digits, period, and for `otpauth://hotp` links the starting counter. The
  name defaults to "issuer: account" as in Google Authenticator and can be
  changed. A bare secret uses the standard SHA1, 6 digits, 30 seconds. Google Authenticator export codes
  (`otpauth-migration://`) aren't supported; add each account's own QR code.
  After saving, the secret is read-only (it can be copied); name, PIN and the
  switches stay editable.
- Optional Policy String (v1/v2) from your IT admin: selects event-based,
  time-based or challenge-response passcodes, 6 or 8 digits, the time step
  (20, 30 or 60 seconds) and the Challenge Code length (6 or 8 digits).
  Without one, profiles use 6-digit event-based passcodes.
- Each profile is one row showing its current passcode, generated offline. Tap
  the row to copy it (optionally as PIN + passcode, per profile). Time-based rows
  refresh on their own and show a countdown. Challenge-response rows show dots;
  tap one and enter the Challenge Code, and the row shows its passcode, ready
  to copy; its ✓ clears it for the next challenge.
- On event-based rows, the ✓ button marks the passcode as used: it advances
  the counter to the next one, with an Undo snackbar. The › button at
  the right of each row opens its edit page. Long-press a row to start
  selecting: tap rows to add or remove them, delete the selection from the
  trash button (after a confirmation), and long-press and drag any row to
  move it (one row at a time; saved right away). ✕, Back, or deselecting everything ends
  selection.
- Optional app lock ("Require authentication to open the app" in Settings):
  opening the app, and coming back to it from the background, shows a lock
  screen (no profile names) and asks for a strong biometric or the screen
  lock; one authentication shows everything until the app goes to the
  background again. Every profile's Activation Code, key or secret key, and
  PIN are encrypted with an AndroidKeyStore key bound to that authentication.
  If the screen lock is removed, the lock screen offers to delete the sealed
  profiles and turn the lock off; they can no longer be decrypted and
  can only be deleted, so keep a separate copy of your Activation Codes and
  secret keys. Upgrading from a version with per-profile protection turns the
  lock on if any profile was protected; the others are sealed at the first
  unlock.
- Edit pages are titled by the kind of code (TOTP profile, HOTP profile or
  Challenge-response profile; a time-based MobilePASS profile is a TOTP
  profile). Profiles that use the MobilePASS algorithm (MobilePASS manual or
  auto enrollment, and manual TOTP with "Use MobilePASS format") show a
  non-clickable "MobilePASS format" line at the top; standard TOTP/HOTP
  profiles don't.
  The secret key sits in a read-only field above the digits setting, hidden
  until you tap the eye, with a copy button; standard OTP shows the Base32
  secret and MobilePASS shows its derived key (Base32).
  Manual MobilePASS enrollment retains its Activation Code and Policy String,
  and new auto enrollments retain the original Enrollment String, server URL,
  User ID, Passphrase and registration PIN alongside the token key; these
  inputs follow the same encryption and app-lock behavior as the key.
  The overflow menu has up to three items: "MobilePASS registration info"
  (MobilePASS manual and auto enrollments only), which opens a sheet with
  the registration data to copy; "Copy otpauth link" (standard OTP and
  MobilePASS event-based profiles only), which copies the link straight to the
  clipboard as sensitive data ("Link copied"); and Delete. Standard TOTP/HOTP
  links use the current name and counter while retaining the original
  credential; a MobilePASS event-based profile's link is an equivalent
  `otpauth://hotp` link (SHA-256) for HOTP apps that support it.
- "Add manually" with a typed secret offers a TOTP/HOTP dropdown, 6 or 8
  digits, SHA-1/256/512 and the TOTP period, plus "Use MobilePASS format" for
  a time-based MobilePASS secret (SHA-256, time steps counted the MobilePASS
  way). There is no starting counter field: a manual HOTP profile starts at
  0, and the counter can be changed on its edit page after adding. The Secret
  field stays visible and has a single QR button to choose the camera or a
  photo; imported links supply their own parameters.
- On an existing profile the parameters (digits, algorithm, period,
  challenge length) appear as read-only fields with grey text.
  Existing secrets start hidden with a show/hide eye. New standard OTP
  credentials stay visible while being entered.
- Settings, in this order: the app lock above (off by default);
  "Block screenshots" (off by default; on sets `FLAG_SECURE`); "Tap to reveal
  passcodes" (off by default; codes stay masked until you tap a row, which
  shows and copies the code, and hide again when it changes, or after 30
  seconds for codes that don't change on their own, and whenever the app is
  in the background; a time-based code tapped in its last 3 seconds stays
  shown through the next one too); and clipboard auto-clear (never / 30
  seconds / 1, 2 or 5 minutes; default 1 minute). Auto-clear is best-effort:
  it only clears the clipboard while the app is still running and the
  clipboard still holds what the app copied. If the app is in the background
  when the time is up, it clears once you return; if Android has closed the
  app by then, the copy stays. With the app lock on, the recents thumbnail
  is hidden; Android 12 and older can only do that by blocking screenshots
  too, so there the lock always does.
- English and Traditional Chinese (Taiwan) UI.

## Install

Download the APK from [GitHub Releases](https://github.com/PinLin/simple-pass/releases) and install it. The
release APK is signed with a certificate whose SHA-256 fingerprint is:

```
6C:88:14:42:E7:C4:CB:96:2A:76:8B:D8:62:79:E1:EF:2F:56:1F:A3:2B:22:A7:98:A8:90:D1:DA:FB:7D:75:DE
```

Check with your organization's IT policy that an unofficial client is allowed
before using it. This software comes with no warranty.

## Build / run

Standard Flutter — see [`app/README.md`](app/README.md).

```
cd app
flutter pub get
flutter run --release        # connected Android device
flutter build apk --release  # build/app/outputs/flutter-apk/app-release.apk
```

Release builds need `app/android/key.properties` (gitignored) for signing;
see [`app/README.md`](app/README.md).

Requirements: Dart 3.11.5+, Flutter 3.41.9+. Android only, `minSdk` 30
(Android 11); package id `me.pinlin.simple_pass`.

## Trademarks

SafeNet, MobilePASS and Thales are trademarks of Thales Group or its
affiliates. SimplePASS is an independent project and is not affiliated with,
endorsed by, or sponsored by Thales.

## License

MIT — see [`LICENSE`](LICENSE). No SafeNet/MobilePASS assets are
redistributed; this is an independent client for the Activation Code and
Enrollment String formats (registration uses the public DSKPP protocol,
RFC 6063).
