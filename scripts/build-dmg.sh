#!/usr/bin/env bash
# build-dmg.sh - builds UP Sysdash and packages it as an installer DMG.
# Usage: ./build-dmg.sh [version] [validated-app-path] [output-dmg-path]
set -euo pipefail

VERSION="${1:-1.1}"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$ROOT_DIR/.." && pwd)"
BUILD_DIR="$PROJ_DIR/build"
APP_NAME="UP Sysdash.app"
APP_SRC="${2:-$BUILD_DIR/Build/Products/Release/$APP_NAME}"
DMG_FINAL="${3:-$PROJ_DIR/releases/up-sysdash-v${VERSION}.dmg}"
VOL_NAME="UP Sysdash"
WORK_DIR="$(mktemp -d /tmp/sysdash-package.XXXXXX)"
STAGE_DIR="$WORK_DIR/stage"
trap 'rm -rf "$WORK_DIR"' EXIT

# Pass a previously validated app as argument 2 to package those exact bytes.
if [ $# -lt 2 ]; then
    echo "Building UP Sysdash v${VERSION}..."
    xcodebuild -project "$PROJ_DIR/sysdashv1.xcodeproj" -scheme sysdashv1 \
        -configuration Release -derivedDataPath "$BUILD_DIR" \
        ARCHS=arm64 MARKETING_VERSION="$VERSION" build > "$WORK_DIR/build.log" 2>&1 || {
            cat "$WORK_DIR/build.log"
            exit 1
        }
    grep -E '(error:|warning:|BUILD)' "$WORK_DIR/build.log" || true
fi
if [ ! -d "$APP_SRC" ]; then
    echo "App not found: $APP_SRC" >&2
    exit 1
fi
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_SRC/Contents/Info.plist")
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "App version $APP_VERSION does not match requested DMG version $VERSION" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_SRC"
test -x "$APP_SRC/Contents/Resources/macmon"
"$APP_SRC/Contents/Resources/macmon" --version

# Write README
echo "Writing README..."
cat > "$WORK_DIR/README.txt" << 'EOF'
UP Sysdash
unboundplanet.com


What is Unboundplanet Sysdash?

UP Sysdash is a system monitor for Apple Silicon. It sits in your
menu bar and shows what your machine is actually doing - CPU, GPU,
RAM, power, temps, network, battery. No subscriptions. No cloud.
No accounts. No bloat. Just your data, on your screen.


INSTALL

Drag UP Sysdash to the Applications folder in this window,
then open it from there. On first launch it will ask if you
want it to start at login. That is it.

macOS will block the app on first open with a message like
"this app has been blocked". This happens because UP Sysdash
is not signed with an Apple Developer certificate. I am not
paying Apple $99 a year to distribute a free app.

Here is how to open it anyway:

  1. Try to open UP Sysdash - it will be blocked.
  2. Open System Settings.
  3. Go to Privacy & Security.
  4. Scroll down until you see a message about UP Sysdash
     being blocked.
  5. Click "Open Anyway".
  6. Authenticate with your password.

You only have to do this once.


UPDATES

Right-click the menu bar stats, then Check for Updates.
Or open the dashboard, go to About, Check for Updates.


UNINSTALL

Drag UP Sysdash from Applications to Trash.
Prefs live at ~/Library/Preferences/unboundplanet.sysdash.plist
Delete that too if you want a clean wipe.


UNDER THE HOOD

UP Sysdash uses macmon to read Apple Silicon performance counters.
macmon is open source, built by vladkens.
  https://github.com/vladkens/macmon
  MIT licensed.

UP Sysdash is also MIT licensed.
Source code: github.com/theodor-ubp/sysdash


REQUIREMENTS

macOS 12.4 or later. Apple Silicon only (M1 or newer).


made with love on unboundplanet.com
EOF

# Stage the tested app and build the branded Finder layout.
echo "Staging UP Sysdash v${VERSION}..."
mkdir -p "$STAGE_DIR" "$(dirname "$DMG_FINAL")"
ditto "$APP_SRC" "$STAGE_DIR/$APP_NAME"
ln -s /Applications "$STAGE_DIR/Applications"
{ printf 'Version %s\n\n' "$VERSION"; cat "$WORK_DIR/README.txt"; } > "$STAGE_DIR/README.txt"

TOOL_PYTHON="$PROJ_DIR/.artifacts/dmg-tools/bin/python"
if [ ! -x "$TOOL_PYTHON" ]; then
    python3 -m venv "$PROJ_DIR/.artifacts/dmg-tools"
fi
if ! "$TOOL_PYTHON" -c 'import dmgbuild' 2>/dev/null; then
    "$TOOL_PYTHON" -m pip install 'dmgbuild==1.6.7' 'ds-store==1.3.3' 'mac-alias==2.2.3'
fi
swift "$ROOT_DIR/make_dmg_bg.swift" "$WORK_DIR/background.png"
"$TOOL_PYTHON" "$ROOT_DIR/dmg_layout.py" "$WORK_DIR/release.dmg" \
    "$STAGE_DIR/$APP_NAME" "$STAGE_DIR/README.txt" "$WORK_DIR/background.png"
hdiutil verify "$WORK_DIR/release.dmg"
mv "$WORK_DIR/release.dmg" "$DMG_FINAL"
(cd "$(dirname "$DMG_FINAL")" && shasum -a 256 "$(basename "$DMG_FINAL")") > "${DMG_FINAL}.sha256"
echo "Done: $DMG_FINAL"
