#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${APP_VERSION:?Set APP_VERSION to the release version without a v prefix}"
[[ "$(uname -s)" == Darwin && "${GITHUB_ACTIONS:-false}" != true ]] || { echo 'Build release archives on a local Mac, not in CI.' >&2; exit 1; }
[[ "${APP_SIGNING_IDENTITY:--}" == - ]] || { echo 'Public packages use local ad-hoc signing only, without a Developer ID certificate.' >&2; exit 1; }
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
assert (app / "Contents/Resources/pi-hook.ts").is_file(), "Missing Pi hook extension"
assert "NSAppleEventsUsageDescription" not in main, "Host-app activation does not need Automation permission"
for path in app.rglob('*'):
    if path.is_file():
        assert b'/Users/' not in path.read_bytes(), 'Local build paths must not be published: ' + str(path.relative_to(app))
for bundle in [app, app / "Contents/PlugIns/DynamicAgentsWidgets.appex"]:
    for language in ["en", "zh-Hans"]:
        assert (bundle / "Contents/Resources" / (language + ".lproj") / "Localizable.strings").is_file(), "Missing app or Widget localization"
PY
[[ "$(lipo -archs "$app/Contents/MacOS/DynamicAgents")" == "arm64" ]]
[[ "$(lipo -archs "$app/Contents/PlugIns/DynamicAgentsWidgets.appex/Contents/MacOS/DynamicAgentsWidgets")" == "arm64" ]]
codesign --verify --deep --strict "$app"
mkdir -p dist/releases
archive="DynamicAgents-$APP_VERSION-arm64.dmg"
if [[ -e "dist/releases/$archive" ]]; then trash "dist/releases/$archive"; fi
staging="$(mktemp -d "$PWD/dist/releases/.dmg-stage.XXXXXX")"
trap 'trash "$staging"' EXIT
ditto "$app" "$staging/DynamicAgents.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname 'Dynamic Agents' -srcfolder "$staging" -format UDZO "dist/releases/$archive"
hdiutil verify "dist/releases/$archive"
(cd dist/releases && shasum -a 256 "$archive" > "$archive.sha256")
python3 - "$app" "dist/releases/$archive.manifest.json" <<'PY'
import json
import plistlib
import subprocess
import sys
from pathlib import Path
app = Path(sys.argv[1])
with (app / 'Contents/Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
for bundle in [app, app / 'Contents/PlugIns/DynamicAgentsWidgets.appex']:
    signature = subprocess.run(['codesign', '-dv', str(bundle)], capture_output=True, text=True, check=True)
    assert 'Signature=adhoc' in signature.stderr, 'Unexpected certificate signing'
manifest = {
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'sourceDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip()),
    'architecture': 'arm64', 'minimumMacOS': info['LSMinimumSystemVersion'],
    'sdk': info.get('DTSDKName', 'unknown'),
    'builtLocally': True, 'signing': 'ad-hoc', 'notarized': False, 'format': 'dmg',
}
Path(sys.argv[2]).write_text(json.dumps(manifest, indent=2) + '\n')
PY
echo "Packaged dist/releases/$archive"
