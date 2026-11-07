#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${APP_VERSION:?Set APP_VERSION to the release version without a v prefix}"
bash scripts/build-app.sh native
app="dist/DynamicAgents.app"
python3 - "$app" "$APP_VERSION" <<'PY'
import plistlib
import sys
from pathlib import Path
app = Path(sys.argv[1])
with (app / "Contents/Info.plist").open("rb") as stream:
    main = plistlib.load(stream)
with (app / "Contents/PlugIns/DynamicAgentsWidgets.appex/Contents/Info.plist").open("rb") as stream:
    widget = plistlib.load(stream)
assert main["CFBundleShortVersionString"] == widget["CFBundleShortVersionString"] == sys.argv[2], "Version mismatch"
assert main["CFBundleVersion"] == widget["CFBundleVersion"], "Build mismatch"
assert widget["CFBundleIdentifier"] == main["CFBundleIdentifier"] + ".widgets", "The widget must belong to the main app"
assert not list((app / "Contents/Helpers").glob("*.app")), "A native release must not embed an auxiliary application"
assert main["NSSupportsLiveActivities"] is True, "A native release must support Live Activities"
assert tuple(map(int, main["LSMinimumSystemVersion"].split("."))) >= (27, 3), "Incorrect deployment target"
PY
[[ "$(lipo -archs "$app/Contents/MacOS/DynamicAgents")" == "arm64" ]]
[[ "$(lipo -archs "$app/Contents/PlugIns/DynamicAgentsWidgets.appex/Contents/MacOS/DynamicAgentsWidgets")" == "arm64" ]]
codesign --verify --deep --strict "$app"
mkdir -p dist/releases
archive="DynamicAgents-$APP_VERSION-arm64.zip"
if [[ -e "dist/releases/$archive" ]]; then trash "dist/releases/$archive"; fi
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/releases/$archive"
(cd dist/releases && shasum -a 256 "$archive" > "$archive.sha256")
echo "Packaged dist/releases/$archive"
