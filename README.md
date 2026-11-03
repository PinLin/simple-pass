# SimplePASS

An unofficial Android OTP generator compatible with SafeNet MobilePASS
Activation Codes and Enrollment Strings. It generates event-based,
time-based and challenge-response one-time passcodes on the device, and also
holds standard TOTP/HOTP tokens (RFC 6238/4226, compatible with FreeOTP and
Google Authenticator).

The app works offline. The only network access is registering an Enrollment
String: SimplePASS then talks to the server that string names (https only),
once, to receive the profile's key.

Permissions: `INTERNET` (Enrollment String registration only), `USE_BIOMETRIC`
(app lock) and `CAMERA` (QR code scanning, requested only when you scan).

## Features

- **MobilePASS – Manual enrollment**: add a profile from an Activation Code
  (`XXXX2-XXXX2-XXXX2-XXXX2`), generate a new one for self-enrollment, plus
  an optional PIN and Policy String.
- **MobilePASS – Auto enrollment**: add a profile from an Enrollment String;
  SimplePASS registers with the DSKPP protocol (RFC 6063).
- **Add manually**: a standard TOTP/HOTP token from a QR code (camera or
  photo), an `otpauth://` link or a Base32 secret. `otpauth-migration://`
  export codes aren't supported.
- Profiles whose codes are standard TOTP/HOTP can be copied as an
  `otpauth://` link.
- Optional app lock with biometrics or the screen lock; secrets are
  encrypted with an AndroidKeyStore key bound to it. If the screen lock is
  removed, sealed profiles can't be decrypted, so keep a copy of your
  Activation Codes and secret keys.
- Block screenshots, tap to reveal passcodes, and clipboard auto-clear.
- English and Traditional Chinese (Taiwan) UI.

The app includes FreeDroidWarn, which shows a dialog about Android's
developer verification policy on the first launch of each new version. It
makes no network connection.

## Install

Download the APK from [GitHub Releases](https://github.com/PinLin/simple-pass/releases). The release APK is
signed with a certificate whose SHA-256 fingerprint is:

```
6C:88:14:42:E7:C4:CB:96:2A:76:8B:D8:62:79:E1:EF:2F:56:1F:A3:2B:22:A7:98:A8:90:D1:DA:FB:7D:75:DE
```

Check with your organization's IT policy that an unofficial client is allowed
before using it. This software comes with no warranty.

## Build

See [`app/README.md`](app/README.md).

## Trademarks

SafeNet, MobilePASS and Thales are trademarks of Thales Group or its
affiliates. SimplePASS is an independent project and is not affiliated with,
endorsed by, or sponsored by Thales.

## License

MIT; see [`LICENSE`](LICENSE). No SafeNet/MobilePASS assets are
redistributed.
