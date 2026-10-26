# UP Sysdash - Apple Silicon System Monitor

Your Mac's stats in your menu bar. CPU, GPU, RAM, power, temps, network, battery - live, native, offline.  
No cloud. No accounts. No bloat. Just your data, on your screen.

[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)](#requirements)
[![Arch](https://img.shields.io/badge/arch-Apple%20Silicon-black)](#requirements)
[![macOS](https://img.shields.io/badge/macOS-12.4%2B-blue)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)
[![Nova · Unbound Planet](https://img.shields.io/badge/Nova-Unbound%20Planet-0f6)](https://unboundplanet.com/nova)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20me-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/tehodor9449790)

---

## Overview

**UP Sysdash** is a free native menu bar monitor for Apple Silicon Macs. It sits in your menu bar and shows what your machine is actually doing in real time.

It runs [macmon](https://github.com/vladkens/macmon) (by vladkens, MIT licensed) in the background to read Apple Silicon performance counters directly. UP Sysdash is the interface layer - the menu bar, the dashboard, the settings.

Everything runs locally. Nothing phones home.

---

## What it shows

- **CPU** - overall usage, E/P/S core-tier frequency and utilization where available, temperature, power
- **GPU** - usage, frequency, temperature, power
- **ANE** - Neural Engine power draw
- **Memory** - RAM used, swap
- **System** - total chip power draw
- **Network** - live download and upload speeds
- **Battery** - percentage, charging state
- **Disk** - free space

All values update at your chosen interval (0.5s, 1s, 2s, or 5s). Metric cards offer 60-sample line/area graphs, level bars, segmented bars or values alone.

---

## Download

Grab the latest release from **[GitHub Releases](https://github.com/theodor-ubp/sysdash/releases)**:

- **macOS (Apple Silicon)** - `.app` inside `.dmg`

---

## Quick start

1. Open the DMG and drag **UP Sysdash** to Applications.
2. Open it from Applications. macOS will block it on first run - see [Gatekeeper](#gatekeeper) below.
3. On first launch, an onboarding window asks if you want the app to start at login.
4. After that, UP Sysdash lives in your menu bar. Left-click to open the dashboard. Right-click for a live stats snapshot and options.

---

## Gatekeeper

macOS will block the app on first open because UP Sysdash is not signed with an Apple Developer certificate. I am not paying Apple $99 a year to distribute a free app.

**How to open it:**

1. Try to open UP Sysdash - it will be blocked.
2. Open **System Settings -> Privacy & Security**.
3. Scroll down to find the blocked app notice.
4. Click **Open Anyway** and authenticate.

You only do this once.

> On macOS 14 and earlier: right-click the app in Finder -> **Open** -> confirm in the dialog.

---

## Settings

**Readings**
- Toggle CPU/GPU usage and temperatures, RAM, power, battery and each network direction independently
- A persistent Example/Live preview shows the tray text

**Text & spacing**
- Choose proportional or monospaced text, font size/weight, character width and tracking
- Adjust processor-label/value gaps, group spacing, separators, temperature suffixes and labels
- Normal system font, degree symbols and compact processor labels are the defaults: `C35° G25°`, or `C5% 35° G10% 25°` with usage enabled

**Cards**
- Choose line graph, area graph, level bar, segmented bar or value only
- Apply a style to all cards or save individual choices, including every available E/P/S tier

**General**
- Refresh interval: 0.5s / 1s / 2s / 5s
- Launch at Login toggle (uses macOS SMAppService)
- macmon status indicator

---

## Requirements

- macOS 12.4 Monterey or later
- Apple Silicon Mac (M1 or newer)
- Intel Macs are not supported

---

## Under the hood

UP Sysdash uses [macmon](https://github.com/vladkens/macmon) to read Apple Silicon performance counters. The macmon binary ships inside the app bundle - no Homebrew or separate install needed.

Version 1.2 bundles **macmon 0.10.0**, including its M6 CPU-tier support and macOS 27 power-counter fixes. CPU and GPU percentages show active residency; CPU usage is weighted by core count. Each reported CPU tier gets its own card, history and Hardware Info row: E/P on M1–M4, E/S on base M5, P/S on M5 Pro/Max, and E/P/S on M6. Unavailable temperatures and VM counters display as `—`.

The app checks for updates on launch. From 1.1 onward, the Download button opens the DMG download directly. Installed 1.0 copies detect newer releases automatically, but their existing Download button opens the release page.

Metrics arrive through macmon's JSON pipe. Each app owns its helper process, recovers from unexpected exits or stalled output, bounds frame buffering, rejects duplicate CPU-tier labels and stops the helper on quit.

## Build and check

```sh
xcodebuild -project sysdashv1.xcodeproj -scheme sysdashv1 -configuration Release -derivedDataPath build ARCHS=arm64 build
Tests/run-smoke-tests.sh
Tests/run-cpu-tier-tests.sh
Tests/run-interface-tests.sh
Tests/run-meter-containment-tests.sh
Tests/run-menu-bar-tests.sh
Tests/run-update-checker-tests.sh
```

The smoke check runs the production monitor against the bundled helper and exercises JSON decoding, nullable temperatures, synthetic M6 and VM streams, tier histories, live readings, refresh changes, stalled/oversized output, crash recovery, and process cleanup. It requires an Apple Silicon Mac with working macmon power counters.

The CPU-tier checks cover M6 E/P/S, both M5 layouts, a single-tier VM, canonical-only JSON and the legacy 0.9 format. M6 fixtures follow upstream's schema and sample ratios; they are not measurements from an M6. Live hardware verification was performed on an M4. Upstream currently derives M6 P-core frequencies from an assumed P-complex table, so absolute M6 frequency accuracy still needs validation on physical hardware.

The interface check verifies fixed refresh-control geometry through changing readings and selections at multiple window sizes and in light/dark appearances. The meter containment check (macOS 13+) tests rendered pixels at chart boundaries, including 0/100% and invalid input. `Tests/run-interface-preview.sh m6` builds a separate synthetic-input QA app at `.artifacts/InterfacePreview.app`; open it to inspect the production dashboard and Hardware Info on an M4. Pass `m6 extremes` for 0/50/100% CPU tiers and full-scale meters. This test app is never included in the installer. Use the running window for visual checks; cached NSView bitmaps do not reliably capture composited SwiftUI layers.

All dashboard cards default to the same history graph style, including Swap, Battery and Disk Free. Swap tracks used/allocated swap, Battery tracks charge while present, and Disk Free tracks free/total capacity. Their histories use the same bounded 60-sample buffers and refresh cadence as the other meters.

The menu bar uses the normal proportional system font by default and groups processor usage and temperature: `C5% 35° G10% 25°`, followed by the existing RAM, power, battery and network formats. Temperature-only selections retain their C/G label. Settings now has Readings, Text & spacing, Cards and General pages, with a persistent Example/Live tray preview. Font size, weight, optional monospace, character width/tracking, gaps, separators, temperature suffixes and labels are configurable. Existing metric selections and separators migrate without losing preferences.

Cards can use a line graph, area graph, level bar, segmented bar or value only. Choose a style for all cards or customize each card, including every available E/P/S tier. Styles persist independently of tray preferences. Current bars use the same normalized scales as history graphs; Settings explains those scales. Unavailable telemetry has no chart or level fill. The existing line graphs remain the default.

Package a release with `scripts/build-dmg.sh 1.2`. The script builds the app and creates a DMG with a small PNG background and saved Finder layout. Pass a validated `.app` path as the second argument to package that exact build. Packaging dependencies stay in `.artifacts/`.

---

## License

MIT. See [LICENSE](LICENSE.md).

macmon is also MIT licensed - [github.com/vladkens/macmon](https://github.com/vladkens/macmon).

---

made with love on [unboundplanet.com](https://unboundplanet.com)
