# Live Activity

## User behavior

The genuine system activity shows running sessions and recent completions, localized from the payload language. Empty eligible feeds hide the activity while monitoring continues. Session rows activate the host App in the background handoff path; only the dashboard link opens the dashboard.

## Native journey

Use macOS/SDK 27.3+, the native App and Widget, ActivityKit authorization, and a trusted Hook with a controlled running session and known host. Follow [native verification](../../../../docs/NATIVE-VERIFICATION.md). Installing replaces the current App; use the task's existing authorization. The Companion contains no Widget.

Run scripts/test-live-activity-lifecycle.py for production-controller recovery cases with a transport double, keeping that evidence separate from the system journey. Check native lifecycle reports for authorization/start/update/end, systemEndRecovered, manualRestarted, hiddenWhenEmpty and createdInBackground. The latter must create while the main App is already inactive and no system activity exists. lifecyclePassed and backgroundHandoff.passed report separate checks; the deliberate ActivityKit end exercises the real end transition, not an unprompted OS failure. Check the recorded activity's chronod logs. Independently click a freshly hit-tested visible system row, require Widget start, main completion and ACK, exact foreground host PID, preserved host window selection/count and no dashboard activation. Repeat warm, repeated and cold actions. Record actual physical clicks separately from direct calls and AX actions.

## Boundaries

Production view renders can verify language/layout without proving system presentation. Historical release click evidence cannot establish a new binary's click behavior. UI probes need Accessibility; App activation itself does not. Stop at a locked session or missing probe permission and report the unmet precondition.
