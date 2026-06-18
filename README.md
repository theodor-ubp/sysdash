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

- **CPU** - overall usage, E-core and P-core frequency and utilization, temperature, power
- **GPU** - usage, frequency, temperature, power
- **ANE** - Neural Engine power draw
- **Memory** - RAM used, swap
- **System** - total chip power draw
- **Network** - live download and upload speeds
- **Battery** - percentage, charging state
- **Disk** - free space

All values update at your chosen interval (0.5s, 1s, 2s, or 5s). Metric cards include 60-sample sparklines for at-a-glance history.

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

**Menu Bar tab**
- Toggle which stats appear in the menu bar independently: CPU, GPU, temps, RAM, power, battery, net down/up
- Choose a separator between stats: hyphen, pipe, slash, or none
- Live preview updates as you configure

**General tab**
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

---

## License

MIT. See [LICENSE](LICENSE.md).

macmon is also MIT licensed - [github.com/vladkens/macmon](https://github.com/vladkens/macmon).

---

made with love on [unboundplanet.com](https://unboundplanet.com)
