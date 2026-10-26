#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PREVIEW_DIR="$PROJECT_DIR/.artifacts/InterfacePreview.app"
mkdir -p "$PREVIEW_DIR/Contents/MacOS" "$PREVIEW_DIR/Contents/Resources"
SOURCES=()
for source in "$PROJECT_DIR/sysdashv1/"*.swift; do
    if [[ "$source" != */sysdashv1App.swift ]]; then SOURCES+=("$source"); fi
done
xcrun swiftc -O -target arm64-apple-macosx12.4 "${SOURCES[@]}" "$PROJECT_DIR/Tests/InterfacePreview.swift" -o "$PREVIEW_DIR/Contents/MacOS/interface-preview"
cp "$PROJECT_DIR/Tests/Fixtures/${1:-m6}.json" "$PREVIEW_DIR/Contents/Resources/sample.json"
if [[ "${2:-}" == "extremes" ]]; then
    /usr/bin/python3 - "$PREVIEW_DIR/Contents/Resources/sample.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); sample = json.loads(p.read_text())
for tier, ratio in zip(sample['cpu_tiers'], [0, 0.5, 1]):
    tier['active_ratio'] = ratio
sample['cpu_active_ratio'] = sum(t['active_ratio'] * i['cores'] for t, i in zip(sample['cpu_tiers'], sample['soc']['cpu_tiers'])) / sum(i['cores'] for i in sample['soc']['cpu_tiers'])
sample.update(gpu_active_ratio=1, cpu_power=30, gpu_power=20, ane_power=8, all_power=58, sys_power=65)
sample['temp'] = {'cpu_temp_avg': 100, 'gpu_temp_avg': 100}
sample['memory']['ram_usage'] = sample['memory']['ram_total']
p.write_text(json.dumps(sample))
PY
fi
cat > "$PREVIEW_DIR/Contents/Resources/fixture-helper" <<'PY'
#!/usr/bin/python3
import json, os, sys, time
with open(os.path.join(os.path.dirname(__file__), 'sample.json')) as source:
    line = (json.dumps(json.load(source)) + '\n').encode()
interval = int(sys.argv[-1]) / 1000
while True:
    os.write(1, line)
    time.sleep(interval)
PY
chmod +x "$PREVIEW_DIR/Contents/Resources/fixture-helper"
/usr/bin/python3 - "$PREVIEW_DIR" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1]) / 'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleIdentifier':'unboundplanet.sysdash.interface-preview',
    'CFBundleExecutable':'interface-preview', 'CFBundleName':'SysDash Interface Preview',
    'CFBundlePackageType':'APPL', 'CFBundleShortVersionString':'1.2', 'NSHighResolutionCapable':True}))
PY
codesign --force --sign - "$PREVIEW_DIR"
echo "$PREVIEW_DIR"
