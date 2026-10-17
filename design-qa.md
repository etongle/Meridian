# Meridian 1.3.0 · Seconds orbit

final result: passed

## Comparison target

- Selected visual truth: third displayed generated design, `qa/seconds-orbit-reference.png`.
- Native implementation: `qa/seconds-orbit-two-clocks.png`.
- Full-view comparison: `qa/seconds-orbit-comparison-initial.png`.
- Native viewport: 360 × 210 logical points, two 180-point columns. The existing native frame is preserved; the generated mockup's outer canvas is not application UI.
- Matched state: English, dark appearance, New York / Shanghai, 2026-10-16T23:44:36Z, full Gregorian dates, 21°C / 23°C Overcast example weather.

## Findings and comparison history

- [P2] Initial seconds ring and value were smaller than the selected visual target. Evidence: `qa/seconds-orbit-initial.png` and `qa/seconds-orbit-comparison-initial.png`. The small value is harder to read at native desktop size. Fix applied: increase the ring from 36 to 42 points and center digits from 13 to 15 points, while retaining the main time and full date. Post-fix evidence: `qa/seconds-orbit-two-clocks.png` and `qa/seconds-orbit-comparison.png`. The larger ring and center value are readable at native size; no date or divider overlap remains.

## Required fidelity surfaces

- Typography: existing native system fonts and 38-point main time retained; seconds use monospaced medium-weight digits. The post-fix digits match the intended subordinate hierarchy. The main time remains regular weight, following the established native product rather than the generated mock’s heavier antialiasing.
- Spacing: date remains complete and left aligned; ring sits at the lower right, without adding panel width or height.
- Colors: existing charcoal surface, warm ivory digits, muted gray date, and icy-blue active ticks.
- Image quality: existing SF Symbols and app icon reused. The changing seconds ring is functional native data visualization, not a raster icon or a substitute for a source image asset.
- Copy: English uses `s`; Simplified Chinese uses `秒`. Accessibility reads HH:mm:ss.

## Implementation checklist

- Completed: seconds model, isolated one-second desktop timeline, native 60-tick ring, common-mode synchronization timer, minute/midnight rollover checks.
- Completed: 80 model checks and single-instance checks; universal build.
- Completed: post-fix source comparison with source and implementation in the same browser comparison frame. Ring, value and both date lines are clearly readable, so a separate magnified crop is unnecessary.
- Completed: single-clock 220 × 210 layout (`qa/seconds-orbit-single.jpg`), four-clock 720 × 210 layout (`qa/seconds-orbit-four-clocks.png`), and Simplified Chinese two-clock layout (`qa/seconds-orbit-zh.jpg`). Full dates, weekday/offset and the localized 秒 unit remain visible.
- Completed: production installation and live seconds (`qa/seconds-orbit-live.jpg`, `qa/seconds-orbit-live-state.txt`). After the menu stayed open, both clocks advanced from 20:52:10 / 08:52:10 to 20:52:23 / 08:52:23. Initial launch also crossed from 20:51:52 into the next minute. The center and highlighted ticks remain synchronized.
- Completed: normal release has no preview flags or fixed-date overrides; current clock selections, menu bar selections and panel position are retained.

## Residual differences and gaps

- P3, accepted: the native 360 × 210 frame is intentionally preserved. The generated reference’s containing canvas and slightly shorter frame are not literal application dimensions. Native material and system font antialiasing vary with the display; enlarged 1× captures are softer than the high-resolution generated image.
- No actionable P0/P1/P2 findings remain.
- Minute/midnight rollover is covered by executable checks. Physical sleep/wake and every possible display scale were not separately exercised in this pass.

## Historical QA

Earlier world-clock design history is preserved in `qa/design-qa-before-seconds.md`.
