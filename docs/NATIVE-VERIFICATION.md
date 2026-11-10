# Native Live Activity verification

Use macOS 27.3+ and a corresponding SDK. The build script selects a suitable local Xcode without changing the global toolchain.

Build and install with bash scripts/install-app.sh. Installation replaces the existing App and stops its validated processes, so use the authorization in the current task. Prepare a supported, trusted Hook and a controlled running session with an available host App.

Use scripts/install-app.sh with --verify-live-activity and an ignored .build report path to verify real ActivityKit authorization, start/update/end, empty-list hiding, background recovery and a direct host-App action. The native journey deliberately ends an activity through ActivityKit and verifies recovery, explicitly recreates it, hides the main App before requesting a new activity, and checks background creation independently of later updates. This background-creation case uses a process that has already been in the foreground. Cold-background creation is a separate journey: stop only the owned main App, launch its installed URL with activates=false/hides=true, capture the lifecycle log and then explicitly open the App. A visibility rejection before the foreground visit must produce a clear message and no repeated background requests; the foreground visit must retry. Direct actions do not establish system Widget clicks.

Run python3 scripts/test-live-activity-lifecycle.py for deterministic production-controller tests against an isolated transport double. These cover registry loss, propagation grace, end/dismissal differences, retries and cancellation without accessing real activities. Imports and platform availability alone are redirected in test copies; this does not establish actual system presentation.

Check chronod logs for the recorded activity using scripts/check-widget-log.py. Rendering and clicks require independent system UI evidence: click a freshly resolved visible activity row, observe Widget execution, main action completion and ACK, then check the exact host PID and absence of dashboard activation. Repeat with the main App running and stopped. Record physical clicks separately from AX actions and direct calls.

The product's host activation requires no Accessibility or Automation grant. The development UI probe needs its own Accessibility authorization and an unlocked GUI session. Report unavailable preconditions; user authentication remains with the user.
