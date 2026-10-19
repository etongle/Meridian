# Mac Location — 1.5.0-beta.7 validation

Status: **automated checks, composite-search UI, apply, fresh Core Location / Maps verification and original-settings restoration passed on macOS 27.0.1**.

## Completed

- 100 existing model/localization/date/weather/layout checks and the single-instance suite passed.
- 62 additional location checks passed, covering composite/international queries, country/state disambiguation, response validation and persisted result names, finite/range validation, partial-write rollback, refresh failure, first-session backup retention, missing-backup no-op, restore failure, macOS 27 absent-preference errors, full-precision XML, kernel locking, atomic protected backups, symlink/hard-link rejection and command escaping. The exact Cupertino coordinate round trip also passed using real `defaults` commands against an explicitly named temporary plist.
- Both the app and the separately signed helper were built for arm64 and x86_64; deep strict signature verification passed.
- Calling the helper without elevation refused both apply and restore before accessing system preferences.
- Verified the beta version, canonical bundle ID, absence of preview/fixed-clock overrides and bundled upstream MIT notice.
- Installed the beta in Applications after backing up the existing app and preferences.
- Native Chinese UI: searched 巴黎 / Paris and selected Paris. The initial selection-only screenshot predates the privileged integration attempt.
- Entered invalid latitude 91 and longitude 0: Apply stayed disabled. Entered valid southern coordinates: the preview updated and Apply became available. These were UI-only tests.
- Existing independent Shanghai clock and prior user clock choices were preserved.

## Privileged integration on macOS 27.0.1

The owner selected Paris for the live test. Native administrator authorization was exercised. The initial beta refused missing preference values because macOS 27 changed the `defaults` error format; beta.2 fixed absence parsing without treating permission/bootstrap failures as absent values. The read-only compatibility check then reported that all fixed simulation keys could be read.

Applying Paris did not complete successfully. The app reported recovery required and retained its original protected backup. This is not evidence that Core Location returned Paris. Beta.3 added sanitized apply/rollback/restore stage diagnostics without logging coordinates or raw system output. The restore attempt read back the original values successfully, then failed at `restartPreferences:launchctl:1:rejected`. Beta.4 used the reference project's ordinary SIGTERM of root-owned cfprefsd, which passed, then failed at `restartLocation:launchctl:1:rejected`. Beta.5 uses ordinary SIGTERM for the fixed `_locationd`-owned locationd process as well, with PID replacement required before reporting success. No forced kill or security-setting change is used.

The owner subsequently changed the test target to Cupertino, California, United States. The manual coordinate is the public [Cupertino City Hall map location](https://www.cupertino.gov/Events-directory/City-of-Cupertino-70th-Anniversary), 37.3183833, −122.028425. This is a public test coordinate, not a device location reading. Beta.5's apply was rolled back because the numeric readback did not match; rollback and both service refreshes succeeded. A temporary-file probe established that `-float` narrows values and macOS 27 `defaults read` rounds its output. Beta.6 uses XML real literals and XML export instead, retaining strict readback validation.

The explicit Verify action initially could not access Location Services. Native System Settings inspection confirmed that both the global Location Services switch and Meridian's individual permission were off. The owner explicitly approved temporarily enabling both and completed the native Touch ID/password verification. Both were then enabled for the test; Maps' existing individual permission was already on.

Beta.6's Apply completed with matching numeric readback and both service refreshes. Verify immediately reported a fresh Core Location target match. Maps was launched and its current-location tracking button was enabled without entering any map search query. Its blue "My location" dot appeared beside Cupertino Library, matching the public City Hall test coordinate. This independently confirms a location consumer beyond Meridian on this Mac. No real device coordinate was persisted or included in evidence.

Restore completed after the owner approved the native administrator prompt. Original simulation values were written and exactly read back, both services refreshed, and the helper then removed its private session backup. The app reported original settings restored and subsequently quit without an active-session warning. No fresh real-device coordinate was recorded after restoration. Maps was quit, and native System Settings confirmed the global Location Services switch and Meridian permission returned to their original off states; Maps' pre-existing individual permission remained unchanged.

Beta.7 adds composite city queries using Open-Meteo's GeoNames-based geocoding with explicit country and state/province qualifiers. With Location Services off, the exact input **Cupertino, CA - United States** plus Return produced the Cupertino / California / United States candidate in the native Chinese UI. Selecting it displayed **37.323000, −122.032180** and enabled Apply without changing system preferences. This verifies that query/selection does not require device location permission. The named candidate was subsequently applied during interactive testing, and the native Verify action reported a Core Location target match for that coordinate as well.

English native interface labels, controls and the network-failure message were inspected. An English service query returned the correct candidate in the direct service check; an in-app English request encountered a connection failure and showed the localized retry message. The Chinese UI preference was restored. The final app is universal, version 1.5.0-beta.7 build 15, installed in Applications; the local DMG passed image integrity verification.

## Pending

Administrator cancellation remains unexercised. The active-session quit warning and Keep and quit were exercised; the recovery indicator survived the app update. Automated rollback tests use in-memory preferences and private temporary directories, not the system services. Other macOS versions and other location consumers remain unverified.

## Evidence

[Initial Chinese place selection, not applied](mac-location-city-zh.jpg); [exact composite query and selected Cupertino candidate, before application](mac-location-composite-zh.jpg). See [mechanism and recovery documentation](../docs/mac-location.md).

The stable release and stable auto-update feed are not replaced by this beta.
