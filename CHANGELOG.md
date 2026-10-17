# Changelog

## 1.3.0 — 2026-10-16

- Add a compact seconds orbit beside every desktop clock’s full date, with 60 ticks and a two-digit seconds value.
- Refresh desktop clock columns once per second on aligned system-clock boundaries, independently of menu bar rendering and weather requests.
- Expose HH:mm:ss to accessibility and synchronize seconds, time and date at minute and midnight rollovers.
- Keep the clock synchronization timer active during menu tracking and dragging.

## 1.2.0 — 2026-10-16

- Add a native draggable title bar, hand cursor and visible drag/lock hints.
- Snap the desktop panel to screen edges on release, with an optional switch and multi-display recovery.
- Add a prominent Open action, close-to-menu-bar behavior, and Find panel (reset position).
- Reveal desktop clocks above other windows until the next outside click, respecting Always on top.

- Browse 400+ supported worldwide time zones, grouped by geographical region.
- Add English/Chinese city, country and time-zone search, including common legacy names.
- Display country names and current UTC offsets in the picker.
- Add representative coordinates for global weather without a separate geocoding lookup.
- Preserve distinct cities with linked clock rules while avoiding obsolete-name duplicates.
- Bundle IANA and Unicode CLDR source data and license notices.

## 1.1.1 — 2026-10-16

- Add a DMG installer with an Applications shortcut; prefer DMG downloads on the website.
- Enforce a single running instance with a kernel-released process lock; repeated launches reveal the existing app.
- Repair the hosted website entry when Pages publishes the repository root.
- Add repository description and website metadata.

## 1.1.0 — 2026-10-16

- Name the project Meridian and add its orbital-clock app icon.
- Use the application icon in the menu bar.
- Default to English, with live Simplified Chinese language switching.
- Fix dropdown clipping and hosting-view offsets with an explicitly sized panel, bounded positioning and a scrollable clock list.
- Integrate Sparkle automatic update checks and optional background downloads.
- Add a bilingual GitHub Pages site, READMEs and English/Chinese launch artwork.
- License original project code and assets under PolyForm Noncommercial 1.0.0.
- Publish universal macOS release archives, signed appcasts, checksums and OCI packages.
