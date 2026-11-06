#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-native}"
if [[ "$mode" != "native" && "$mode" != "companion" ]]; then
  echo 'Usage: scripts/build-app.sh [native|companion]' >&2
  exit 2
fi
supports_native_sdk() {
  python3 -c 'import sys; v=tuple(map(int, sys.argv[1].split(".")[:2])); sys.exit(0 if v >= (27,3) else 1)' "$1"
}
if [[ "$mode" == "native" ]]; then
  sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
  if ! supports_native_sdk "$sdk_version" && [[ -z "${DEVELOPER_DIR:-}" ]]; then
    for candidate in /Applications/Xcode*.app/Contents/Developer; do
      [[ -d "$candidate" ]] || continue
      candidate_sdk="$(DEVELOPER_DIR="$candidate" xcrun --sdk macosx --show-sdk-version 2>/dev/null)" || continue
      if supports_native_sdk "$candidate_sdk"; then
        export DEVELOPER_DIR="$candidate"
        sdk_version="$candidate_sdk"
        break
      fi
    done
  fi
  if ! supports_native_sdk "$sdk_version"; then
    echo "Native Live Activities require macOS SDK 27.3+. Selected SDK: $sdk_version." >&2
    echo 'Select Xcode 27.3 with DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer, then rerun.' >&2
    echo 'To build the dashboard only: scripts/build-app.sh companion' >&2
    exit 1
  fi
  echo "Using macOS SDK $sdk_version from ${DEVELOPER_DIR:-$(xcode-select -p)}"
fi
mkdir -p dist
if [[ "$mode" == "native" ]]; then
  python3 scripts/generate-project.py
  xcodebuild -project DynamicAgents.xcodeproj -scheme DynamicAgents \
    -configuration Release -derivedDataPath .build/xcode \
    CODE_SIGNING_ALLOWED=NO build
  destination="dist/DynamicAgents.app"
  if [[ -e "$destination" ]]; then trash "$destination"; fi
  ditto .build/xcode/Build/Products/Release/DynamicAgents.app "$destination"
  /usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 27.3' "$destination/Contents/Info.plist"
  codesign --force --sign - --entitlements Resources/Widget.entitlements "$destination/Contents/PlugIns/DynamicAgentsWidgets.appex"
else
  swift scripts/generate-icon.swift
  iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
  swift build --build-system native -c release -j 4
  bin_path="$(swift build --build-system native -c release --show-bin-path)"
  destination="dist/DynamicAgents-Companion.app"
  if [[ -e "$destination" ]]; then trash "$destination"; fi
  mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"
  cp "$bin_path/DynamicAgents" "$destination/Contents/MacOS/DynamicAgents"
  cp Resources/Info.plist "$destination/Contents/Info.plist"
  cp Resources/AppIcon.icns "$destination/Contents/Resources/AppIcon.icns"
  ditto "$bin_path/DynamicAgents_AgentCore.bundle" "$destination/Contents/Resources/DynamicAgents_AgentCore.bundle"
  /usr/libexec/PlistBuddy -c 'Set :NSSupportsLiveActivities false' "$destination/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 15.0' "$destination/Contents/Info.plist"
fi
codesign --force --sign - "$destination"
codesign --verify --strict "$destination"
echo "Built $destination"
