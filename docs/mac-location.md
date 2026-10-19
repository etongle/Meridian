# Mac Location — experimental preview

This feature attempts to make the **Mac running Meridian** report a selected coordinate through macOS Core Location. It is not an iPhone simulator or a time-zone selector. It requires one-off macOS administrator authorization.

## Availability

Development build: **1.5.0-beta.7**, branch `feature/mac-location`. Stable 1.4.0 remains unchanged. Keep this private-preference experiment separate from the stable auto-update feed.

On this development Mac’s macOS 27.0.1, beta.6 applied the public Cupertino City Hall coordinate, read back the full-precision values and restarted the preference/location services. Meridian received a fresh Core Location fix within its target/accuracy thresholds, and Maps' current-location blue dot appeared in Cupertino. This is a same-device observation, not a guarantee for every macOS version or application. See the [validation record](../qa/mac-location-beta-validation.md) for recovery and permission-restoration status. The reference project reports an observation on macOS 26.6.2 but also marks its package and other versions unverified.

## Use

1. Open **Manage clocks → Mac Location**, or **More → Mac Location…** in the menu bar panel.
2. Choose an offline representative city/time zone, or type a city, state/province and country such as **Cupertino, CA - United States** and click **Search location** or press Return. The explicit online search sends the place query to Open-Meteo's GeoNames-based city search and requires an internet connection, not device location permission. State/province qualifiers and a recognized country filter disambiguate the city. Select the intended result and review its name and coordinates; searching never applies it automatically. Manual decimal latitude/longitude remains available. South and west use negative values.
3. Review the displayed coordinates, then click **Apply to Mac Location** and approve macOS’s administrator prompt yourself. Meridian does not collect or store an administrator password.
4. A successful preference write reads **Settings applied; system location has not been verified**. It does not claim all apps have changed location.
5. Click **Verify system location**. If requested, grant Meridian location permission in the system prompt. Only a fresh, sufficiently accurate Core Location fix within 1 km of the target is treated as a match. Raw device coordinates are not persisted or transmitted by this verification.
6. Refresh location in the target app (for example, Maps’ current-location button).
7. Click **Restore original location** to restore the saved simulation preferences. This may require another administrator authorization. Verify location again in the target app. Quitting with a remembered simulation offers Restore and quit, Keep and quit, or Cancel.

Simulation may persist after quitting or restarting. Apps using IP geolocation, account regions or their own cached signals may disagree. Meridian does not change the IP address or guarantee Find My/cloud-device updates. Automatic time-zone selection and other location consumers may react to a simulated region.

## Privileged scope and recovery

The bundled, separately signed `MeridianLocationHelper` refuses unprivileged operations. The only accepted operations are apply with finite, range-checked numeric coordinates, restore, and a read-only compatibility check. The check reads the fixed simulation preference domains; it does not write them or restart services. Only the six simulation values are retained from the in-memory domain exports. XML real values preserve numeric precision for backup, writing and readback; formatted `defaults read` output and Float32 writes are not used. No arbitrary commands, file paths, preference domains or keys can be supplied to the helper.

Only three current-host preferences in each of `com.apple.locationd` and `com.apple.locationd.notbackedup` for `_locationd` are modified: latitude, longitude and accuracy simulation values. The system preference daemon and location daemon receive normal termination/restart requests; no SIP, AMFI, boot setting, entitlement, TCC database or Find My service is modified. No persistent privileged daemon or passwordless sudo rule is installed.

The FIRST pre-simulation values (including absent keys) are kept in `/var/db/meridian-location/original.json`, in a root-owned 0700 directory with a 0600 backup and a kernel operation lock. Changing targets keeps that original backup. Partial writes or restart failures attempt rollback. A failed restore retains recovery data and is never reported as success. Do not delete or upload the private backup to force a reset.

A developer recovery command is `sudo /Applications/Meridian.app/Contents/MacOS/MeridianLocationHelper restore`. It restores only Meridian’s saved simulation preferences. If no backup exists, it leaves system preferences unchanged. Coordinates passed to an apply operation can appear in process arguments; OS/app logs and caches are outside Meridian’s control.

## Automated validation

- 100 existing clock/date/weather/layout checks and the single-instance suite.
- 62 location checks covering composite/international search inputs, country/state disambiguation, service response validation, saved result names and legacy targets, invalid coordinates, partial-write rollback, refresh failure, first-backup preservation, failed restoration, missing-backup behavior, macOS 27 absent-preference error formats, full-precision XML, locks, protected atomic backup files, symlink/hard-link rejection and authorization-command escaping.
- Memory preference backends and private temporary directories were used. A real `defaults` XML round-trip regression uses an explicitly named temporary plist; these tests never access system location preferences.

## Reference

Mechanism research: [mac-location-spoofer](https://github.com/TimBitBox/mac-location-spoofer), MIT, TimBitBox. See the included attribution and license. This is a private macOS preference experiment, not a supported Apple location-setting API.

Online city search: [Open-Meteo Geocoding API](https://open-meteo.com/en/docs/geocoding-api), based on GeoNames. It supports translated names, country filters and first-level administrative abbreviations. Requests occur only on Search/Return, are spaced at least 1.1 seconds apart and use a small in-memory cache. Queries are not written to a search-history file; the user-selected applied target remains saved for recovery. The free service is for noncommercial use, consistent with this project's license. Street-address lookup is outside this city-search feature.
