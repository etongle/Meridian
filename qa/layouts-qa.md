# Desktop layouts verification — Meridian 1.4.0

Result: **passed**.

## Scope

Extend the existing native clock card with Horizontal, Vertical and Independent clocks. Keep its typography, colors, full date, weather and 42-point seconds orbit. The title-bar layout icon, menu bar More menu and Settings share the same saved choice. No generated UI artwork is used.

## Verified

- 100 model, localization, geometry and layout lifecycle checks passed, plus the single-instance suite.
- A universal Apple Silicon + Intel build passed deep strict code-signature verification.
- Installed the production app in Applications, with no fixture dates or preview flags.
- Switched Horizontal → Vertical → Independent from the native title-bar menu. A two-clock vertical panel is 220 × 384 points; each independent clock is 220 × 210 points.
- Moved New York and Shanghai separately; only the dragged clock changed position. Closing New York left Shanghai visible and updating. Open restored New York without changing selected regions.
- Restarted in Independent mode and compared saved configuration: arrangement, both positions, selected regions, menu bar selection and language were preserved.
- Switched layouts through Settings and visually checked English and Simplified Chinese controls, descriptions and all update options for clipping.
- Found briefly offset independent TimelineView ticks after rebuilding the layout. Replaced them with one shared whole-second sample, observed only by clock cards. The status menu and weather remain independent of second-level redraws.
- Rechecked the final production build: both vertical cards read second 24; both advanced to 28 with the layout menu open. Independent clocks continued advancing after switching back.
- Preserved the user's latest choice after validation: Independent mode, New York closed and Shanghai visible, with all saved positions unchanged.
- Geometry checks cover six-clock stacks taller than the screen, scrolling, horizontal wrapping on narrow displays, an empty desktop and disconnected-screen recovery. Physical monitor disconnection and sleep/wake were not separately exercised in this turn.

## Evidence

- [Vertical, final production build](layout-vertical-live.jpg)
- [Independent New York](layout-independent-new-york.jpg)
- [Independent Shanghai after closing New York](layout-independent-shanghai.jpg)
- [English Settings](layout-settings-en.jpg)
- [Native synchronized clock state](layout-final-state.txt)
- [Upgrade, dragging and restart verification](layout-upgrade-validation.txt)

## Release checks

DMG checksums and the signed update archive were verified. Modified archive bytes were rejected. Release packaging rejects preview flags and noncanonical bundle identifiers. The app remains ad-hoc Apple signed, without Apple notarization.
