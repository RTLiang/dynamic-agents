# Native Live Activity verification

Use macOS 27.3+ and a corresponding SDK. The build script selects a suitable local Xcode without changing the global toolchain.

Build and install with bash scripts/install-app.sh. Installation replaces the existing App and stops its validated processes, so use the authorization in the current task. Prepare a supported, trusted Hook and a controlled running session with an available host App.

Use scripts/install-app.sh with --verify-live-activity and an ignored .build report path to verify real ActivityKit authorization, start/update/end, empty-list hiding, background recovery and a direct host-App action. Direct actions do not establish system Widget clicks.

Check chronod logs for the recorded activity using scripts/check-widget-log.py. Rendering and clicks require independent system UI evidence: click a freshly resolved visible activity row, observe Widget execution, main action completion and ACK, then check the exact host PID and absence of dashboard activation. Repeat with the main App running and stopped. Record physical clicks separately from AX actions and direct calls.

The product's host activation requires no Accessibility or Automation grant. The development UI probe needs its own Accessibility authorization and an unlocked GUI session. Report unavailable preconditions; user authentication remains with the user.
