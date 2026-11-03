# UP Sysdash 1.3

Version **1.3**, build **4** — 3 November 2026.

## Fixed-width menu bar stats

- Added **Fixed width for all stats**, enabled by default for new installations and upgrades from 1.2.
- The entire Sysdash menu-bar item now reserves a constant width instead of resizing with every reading. RAM changes such as `9.9GB` → `10.0GB` no longer move its boundaries or push neighboring menu-bar icons and their anchored windows sideways.
- Default width is **240 points**, configurable from **80–600 points** in **Settings → Text & spacing → Menu bar width**.
- The complete stats string compresses horizontally when it exceeds the selected width, including labels, numbers, units and spacing. Shorter strings retain their normal width inside the reserved area.
- The Settings preview uses the same fitted rendering as the status item. Full readings remain available to accessibility and in the tooltip.
- Turn fixed width off to restore 1.2's automatic sizing. The enabled state and chosen width are saved independently of existing font, spacing and metric selections.
- Existing dashboard cards, chart choices, metric formatting, monitoring and **macmon 0.10.0** are unchanged.

## Verification

- Reproduced the original problem on an actual status item: `9.9` → `10.0` → `9.9` GB changed its frame from **58 → 64 → 58 points**. The fixed-width item remains **240 → 240 → 240 points**.
- Regression checks cover 72 status updates with proportional/monospaced fonts, three configured widths, unavailable readings, battery/network changes, overflow fitting, accessibility, upgrade migration, numeric bounds, persistence, and switching fixed width off/on.
- Existing tray-formatting checks still cover all 512 metric selections. Release build and interface/update-checker checks passed.

Apple Silicon; macOS 12.4 or later. The app remains ad-hoc signed and is not notarized.

DMG SHA-256: `d1281336b3be10e1432723dc29bbc75e5d1d733d7e75c7c858dfa875f8989ee3`.

[Changes since 1.2](https://github.com/theodor-ubp/sysdash/compare/v1.2...v1.3)

---

# UP Sysdash 1.2

Version **1.2**, build **3** — 26 October 2026.

This release includes the complete monitoring, interface and configuration improvements made during the debugging and validation work since 1.1, plus the bundled **macmon 0.10.0** update.

## macmon 0.10.0 and CPU compatibility

- Updated the bundled official arm64 helper from macmon 0.9.0 to [macmon 0.10.0](https://github.com/vladkens/macmon/releases/tag/v0.10.0). Its release-archive checksum was verified; version, source commit, license and archive checksum are recorded in the source tree.
- Adopted macmon's canonical `cpu_tiers` metadata and readings rather than assuming two CPU groups. Each reported tier has its own frequency/utilization card, independent history and Hardware Info row.
- Added three-tier M6 support: E, P and S cores appear separately. Fixed the header/core-count path that omitted M6 P cores; a synthetic 6E/4P/2S configuration now reports all three groups.
- Handle E/P configurations on M1–M4, E/S on base M5, P/S on M5 Pro/Max, and a single unknown CPU tier in a macOS VM. Readings match metadata by tier label.
- Retained decoding compatibility with the older macmon 0.9 JSON format.
- Hardware Info uses the actual maximum of each reported frequency table, including tables that are not sorted. Missing frequency information displays as unavailable instead of inventing a maximum.
- VM power, GPU telemetry and frequencies display as unavailable when the helper cannot supply them. Null temperatures display as `—`; unavailable sensors do not add fabricated zero samples to their histories.
- Retains macmon's rootless power-counter support for macOS 27. Live functional checks were performed on an M4 running macOS 27.0.1.

## Monitoring reliability

- Added a refresh-interval-aware watchdog for a helper that stays running but stops producing samples. Stale readings are cleared, the app shows Offline, and the helper is restarted automatically.
- Unified recovery after unexpected exits and stalled output, with generation checks to prevent callbacks from an obsolete helper from replacing current data.
- Limited pending JSON framing to 1 MiB. Oversized unterminated output now triggers recovery instead of allowing unlimited buffer growth.
- Reject empty or duplicate CPU-tier labels before publishing readings, preventing duplicate SwiftUI identifiers and dictionary-construction crashes.
- Shutdown cancels auxiliary polling, watchdog and retry activity. Changing preferences after shutdown cannot start another helper.
- Hardware metadata remains available during an offline transition.
- Network values become unavailable during helper outages across the dashboard, tray and right-click snapshot, avoiding stale rates presented as current readings.
- Legacy launch-at-login plist generation now uses proper property-list serialization, preserving app paths containing characters such as `&`, `<` and `>`.

## Dashboard and meters

- Fixed chart fills, strokes and endpoint dots escaping their drawing area. Sparkline geometry has an inset and explicit clipping, and handles out-of-range or non-finite input safely. Rounded cards also contain their drawing.
- Standardized Swap, Battery and Disk Free on the same default history-graph presentation as the other cards. Swap shows used/allocated swap, Battery shows charge when present, and Disk Free shows free/total capacity. Histories retain the latest 60 samples.
- Added five visualization choices for every card: **line graph, area graph, level bar, segmented bar and value only**.
- Added an all-cards style chooser and individual per-card overrides. Choices persist separately from tray preferences and include every available E/P/S tier; future tiers inherit the chosen default style.
- Bars show the current normalized reading using the same scales as the history graphs. Settings explains the temperature, power and adaptive network scales. Unavailable and value-only cards do not draw misleading meters.
- Fixed foreground rendering for level and segmented bars and verified their 0%, 50% and 100% states.
- Preserved the fixed-width refresh picker and verified that its segments stay clear of the Refresh label during changing samples, selections, offline transitions and window resizing.

## Tray formatting and Settings

- Restored normal proportional system text as the default. Monospace is now a user preference rather than a forced tray font.
- Grouped processor usage and temperature with compact labels: `C5% 35° G10% 25°`. With only temperature enabled, the format is `C35° G25°`.
- Replaced the default `deg` suffix with the degree symbol and removed the default gap between C/G and the first numeral. Original RAM, power, battery and network formats remain available.
- Replaced the old Settings tabs with **Readings**, **Text & spacing**, **Cards** and **General** pages in a larger dialog.
- Added configurable font size and weight, optional monospace, character width, character tracking, processor-label gap, value/group spacing, separators, temperature suffixes, full CPU/GPU labels, system labels and battery symbols.
- Added a persistent **Example/Live** tray preview that shares the exact formatter and attributed typography used by the real status item.
- Added appearance and card-style resets. Appearance reset preserves the selected readings and separator; card-style reset is independent of tray preferences.
- Existing reading selections and separators survive settings migration. Partial settings receive defaults, numeric appearance values are bounded, and preferences survive app restarts.
- Sidebar page changes reset the content scroll position so the first controls are visible. Long content scrolls while the preview remains visible.

## Validation

The debugging work used systematic investigation, regression checks, performance profiling, independent code review and final artifact verification.

- Release build passed on Apple M4, macOS 27.0.1, with Xcode 27.1.
- CPU-schema checks cover M6 E/P/S, both M5 layouts, VM, canonical-only JSON, legacy JSON, unsorted frequency tables and total core-weighted CPU usage.
- Stream/lifecycle checks cover malformed and oversized output, stalls, duplicate tiers, history bounds, refresh changes, crash recovery and process cleanup.
- Interface checks exercise 180 changing dashboard updates and all five chart styles across M6/M5/VM fixtures, 700/820/1200-point widths, and light/dark appearances.
- Pixel checks cover chart/card containment, accurate bar levels, unavailable states, invalid input and narrow card widths. The original chart-overflow regression reproduced 84 escaped pixels; the corrected renderer has none in the checked cases.
- Tray checks cover all 512 reading combinations, temperature-only labels, missing values, battery formatting, normal-font defaults, optional monospace, width/tracking controls, persistence and reset behavior.
- Live M4 baseline/load/recovery sampling checked finite, bounded utilization, CPU-tier weighting, RAM bounds and internally consistent chip/system power. This was a functional response check, not a calibrated benchmark.
- The DMG was mounted read-only, its app passed strict signature verification, and its contents matched the validated Release build byte for byte. The packaged helper produced live M4 readings.

**Coverage limits:** M6 and M5 coverage is synthetic; no physical M6/M5 was available. Upstream currently uses an assumed P-complex frequency table for M6's middle tier, so absolute frequency/power accuracy still needs physical-hardware validation. Earlier macOS versions were not run during this audit. Legacy macOS 12 launchctl error-status handling remains a pre-existing limitation. The app remains ad-hoc signed and is not notarized.

## Download and updates

- Install **up-sysdash-v1.2.dmg** from this release. Apple Silicon and macOS 12.4 or later are required.
- This is the stable **v1.2** release. Existing copies detect it through **Check for Updates**. Version 1.1 and later open the DMG directly; the already-shipped 1.0 Download button opens the release page.
- The installer keeps the simple branded Finder layout with the app and Applications shortcut. Its background is a 35,182-byte PNG, without a large TIFF.
- DMG SHA-256: `5c8301b0b4d32b26f949aa05dd02f37f7d0f3937264651175baeccdee6f5f75e`.

[Source changes since 1.1](https://github.com/theodor-ubp/sysdash/compare/v1.1...v1.2)
