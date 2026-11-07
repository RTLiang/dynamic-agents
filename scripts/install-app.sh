#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
installation="$HOME/Applications/DynamicAgents.app"
if [[ ! -e "$installation" && -e /Applications/DynamicAgents.app ]]; then
  installation="/Applications/DynamicAgents.app"
fi
if [[ -e "$installation" ]]; then
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installation/Contents/Info.plist")"
  if [[ "$identifier" != "dev.local.dynamicagents" ]]; then
    echo "Another application occupies $installation. Installation stopped." >&2
    exit 1
  fi
  command -v trash >/dev/null
fi
bash scripts/build-app.sh native
swift -e '
import AppKit
import Darwin
import Foundation
func alive(_ app: NSRunningApplication) -> Bool {
    if app.isTerminated { return false }
    var path = [CChar](repeating: 0, count: 4096)
    if proc_pidpath(app.processIdentifier, &path, UInt32(path.count)) > 0 {
        return String(cString: path) == app.executableURL?.path
    }
    return kill(app.processIdentifier, 0) == 0 || errno != ESRCH
}
let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "dev.local.dynamicagents" }
for app in apps { _ = app.terminate() }
let deadline = Date.now.addingTimeInterval(20)
while apps.contains(where: alive) && Date.now < deadline {
    RunLoop.current.run(until: .now.addingTimeInterval(0.1))
}
if apps.contains(where: alive) {
    FileHandle.standardError.write(Data("Dynamic Agents did not quit. Installation stopped.\n".utf8))
    exit(1)
}
'
registration_tool="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
unregister_app() {
  local registration_output widget_output
  local helper="$1/Contents/Helpers/DynamicAgentsHandoff.app"
  if [[ -d "$helper" ]]; then unregister_app "$helper"; fi
  local widget="$1/Contents/PlugIns/DynamicAgentsWidgets.appex"
  if [[ -d "$widget" ]] && ! widget_output="$(LC_ALL=C /usr/bin/pluginkit -r "$widget" 2>&1)"; then
    if [[ "$widget_output" != "remove: no plugin at "* || "$widget_output" == *$'\n'* ]]; then
      echo "$widget_output" >&2
      return 1
    fi
  fi
  if registration_output="$("$registration_tool" -u "$1" 2>&1)"; then return; fi
  if [[ "$registration_output" == *"-10814"* ]]; then return; fi
  echo "$registration_output" >&2
  return 1
}
for duplicate in "$PWD/.build/xcode/Build/Products/Release/DynamicAgents.app" "$PWD/.build/xcode/Build/Products/Release/DynamicAgentsHandoff.app" "$PWD/dist/DynamicAgents.app" "$PWD/dist/DynamicAgents-Companion.app"; do
  if [[ -e "$duplicate" ]]; then unregister_app "$duplicate"; fi
done
if [[ -e "$installation" ]]; then unregister_app "$installation"; fi
swift scripts/stop-app-helpers.swift --stop "$installation" \
  "$PWD/.build/xcode/Build/Products/Release/DynamicAgents.app" "$PWD/dist/DynamicAgents.app"
if [[ -e "$installation" ]]; then trash "$installation"; fi
mkdir -p "$(dirname "$installation")"
ditto dist/DynamicAgents.app "$installation"
codesign --verify --deep --strict "$installation"
"$registration_tool" -f "$installation"
/usr/bin/pluginkit -a "$installation/Contents/PlugIns/DynamicAgentsWidgets.appex"
open "$installation" --args "$@"
echo "Installed $installation"
