# Live Activity

The system island shows running and recently completed agents, expands into session rows, hides when no sessions qualify, and restores when an eligible agent appears.

## Sub-features

- `activity-compact`: counts and short status labels, without clipped text.
- `activity-expanded`: session rows and actions, including overflow.
- `activity-expiry`: configured completion duration and exact expiry.
- `activity-empty-resume`: hide with no eligible agents, restore when one appears.
- `activity-focus`: background row action focuses the correct pane without activating the dashboard.
- `activity-dismiss`: respect user/system dismissal and the enable switch.

## How to get to it (user POV)

- Enable `Live Activity` in the dashboard; qualifying agents make the system display it.
- Open the island to inspect rows and select one; adjust `Show Completed For` in Connection Settings.
- Disable the dashboard switch or choose `Stop Live Activity` from the app's menu.

## Driving it with AX

Preconditions: macOS 27.3+, Xcode with macOS 27.3+ SDK, ActivityKit authorization, the real native App/Widget installed and registered once, a dedicated herdr session with the required agent states, and explicit user permission. The isolated Companion fixture cannot create or render a Widget. Do not double-drive or replace the user's installed App during another session.

- **Build:** `bash scripts/build-app.sh native` builds `dist/DynamicAgents.app`; it does not prove the system can register or render the Widget.
- **Install and lifecycle, only with consent:** `bash scripts/install-app.sh --verify-live-activity "$PWD/.build/live-activity-check.json"`. This replaces the installed app, ends/restarts activities and opens or reuses a dedicated attachment for the currently selected real agent. Wait for the App to become active and require `passed`, `hiddenWhenEmpty`, `resumedInBackground` and `backgroundHandoff.passed` in the report.
- **Render:** capture chronod logs for the reported `monitoringID`, then run `python3 scripts/check-widget-log.py .build/widget-check.log --activity-id "$MONITORING_ID"`; require successful renders and zero failures for that ID. The log-capture command is in `docs/NATIVE-VERIFICATION.md`.
- **Actual presentation:** drive compact and expanded states through the system UI and inspect text clipping, rows, status counts, dismissal, configured expiry and row click. Capture action plus system result. A lifecycle report or `ImageRenderer` preview alone does not prove system presentation. Screen capture permission is separate and must not be changed without approval.

## Gotchas

- ActivityKit system UI and registration are shared with the installed app. Unique Companion bundle IDs are not a substitute for native Widget isolation.
- Completion time is observed by polling; a previously completed agent with unknown completion time is intentionally excluded. Use a controlled running→done transition and verify the actual configured duration.
- The background probe executes `perform()` directly; it cannot prove a physical system-widget click. Document any unexercised path.
- Keep real logs, reports and screenshots under `.build/` and inspect for private session data before sharing.
