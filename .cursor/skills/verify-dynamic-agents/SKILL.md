---
name: verify-dynamic-agents
description: Verify Dynamic Agents' macOS desktop UI, menu, terminal handoff, and Live Activities through user-facing journeys; use after changing the app or investigating a UI regression.
---

# Verify Dynamic Agents

Read [features/README.md](features/README.md), then every feature file relevant to the change. The primary surface is the macOS SwiftUI app; the Widget, herdr CLI boundary and SwiftPM core are additional surfaces. Do not treat a model test or a direct intent call as proof of a system Widget click.

## Launch

Prerequisites: macOS 15+, Xcode command-line tools, `swift`, `codesign`, `trash`, a GUI login, and Accessibility permission for the terminal/agent that launches the helper. The helper checks permission; it never changes system permissions. No network, credentials or real herdr server are needed for the isolated Companion run.

From the repository root, run this entire sequence in one shell; the trap cleans up on failures. The run ID must be fresh, lowercase alphanumeric, and at most 32 characters.

```bash
set -euo pipefail
C="$PWD/.cursor/skills/verify-dynamic-agents/helpers/control"
RUN="v$(date +%s)$$"
E="$PWD/.build/verify-dynamic-agents-evidence/$RUN"
trap '"$C" cleanup "$RUN"' EXIT
"$C" launch "$RUN"
"$C" doctor "$RUN" | tee "$E/doctor-repeat.txt"
"$C" snapshot "$RUN" > "$E/before.json"
"$C" duration "$RUN" | tee "$E/duration.txt"
"$C" snapshot "$RUN" > "$E/after.json"
"$C" cleanup "$RUN"
trap - EXIT
test -s "$E/duration.txt" && grep -q 'PASS: settings-duration' "$E/duration.txt"
echo "Evidence retained: $E"
```

`launch` builds the actual SwiftPM Companion in debug mode, packages a disposable app with a unique bundle identifier, removes its URL registration, signs it ad hoc, launches its executable and waits for the connected `agents-table` with both fixture rows. A standalone app process or build success alone is not ready. The fixture implements the production herdr CLI boundary, accepting explicit `--session default` followed by `api snapshot` and `status --json`; an owned local socket fixture handles `integration.list`, `integration.install` and `integration.uninstall`. It cannot prove actual herdr discovery, focusing or native ActivityKit. `HERDR_BIN` and the fixture trace are scoped to that process. The isolated preferences domain starts empty; launch arguments disable automatic update checks. Desktop hook data and client configuration are scoped to scratch via process-local environment overrides. The app launches through NSWorkspace with its owned bundle ID; real client settings are not read or installed by the fixture. The user's installed App, its settings and actual herdr session are not reused; the test can still bring its own window to the foreground. SwiftPM build output is shared, so avoid simultaneous builds in the same checkout.

## Doctor

Run `"$C" doctor "$RUN"` whenever anything looks wrong. It validates the recorded PID's executable path and bundle ID, Accessibility authorization, the table, a connected fixture and both expected rows. A missing Accessibility grant, locked screen or absent GUI session is a failed precondition: report it instead of changing permissions or unlocking the system. Check `$E/build.log`, `$E/ax-build.log`, `$E/app-launch.log` and `$E/herdr-commands.log` for diagnostics. Never drive an unrelated PID.

## Drive

Use the feature map for exact journeys and remaining manual/exclusive paths. Helpers operate on the isolated PID only:

```bash
"$C" snapshot "$RUN" > "$E/dashboard.json"
"$C" press "$RUN" AXButton 'Connection Settings'
"$C" set "$RUN" completion-window-minutes 7
"$C" press "$RUN" AXButton Cancel
"$C" menu "$RUN"
```

`press` matches an AX role and exact English title, description or help. `set` writes AXValue by accessibility identifier; `role:AXTextField` selects the first matching role. `type "$RUN" AXTextField Build` focuses the field and sends keyboard events to the verification PID, selecting existing text first; pass `''` to clear. Use `type`, not `set`, for the search field: AXValue alone does not trigger SwiftUI search updates. `duration` is a complete save/reopen/cancel user journey that checks the isolated persisted preference. `integrations` exercises list/install/update/remove through the real management UI and the owned socket fixture; see [features/integrations.md](features/integrations.md). `desktop-hooks` exercises the four desktop adapters against isolated client configurations; see [features/desktop-hooks.md](features/desktop-hooks.md). `menu` reads the app's status item. `snapshot` emits the AX tree as JSON; it can include sensitive session names if a non-fixture app is ever substituted.

## Evidence

Keep proof under `$E`, which is inside ignored `.build/`. Capture each action and observed result, AX snapshots before/after, and the persisted side effect for changes. `duration.txt` shows open, enter, Save, reopen, Cancel and the saved value; `herdr-commands.log` must contain only `--session default api snapshot` and `--session default status --json`; status is also queried for precise terminal discovery. For that feature also inspect `integration-actions.jsonl` and `integration-state.json` to verify mutations; merely opening the manager must not install anything. Check it, rather than assuming a dry run is harmless. Screenshots require Screen Recording authorization and may contain private data; ask before changing permission or sharing screenshots. AX trees and successful chronod reloads are not system-island screenshots. Never commit local screenshots, logs, paths or real session data.

## Cleanup

`"$C" cleanup "$RUN"` terminates only the recorded matching verification executable and owned integration-fixture server, removes its unique preferences domain and moves scratch state and the owned socket to Trash. It refuses a reused PID, an unresponsive process or symlinked scratch path. Evidence survives at `$E`; confirm it still exists. Never kill by process name or clean another instance. Run cleanup after each failed iteration; use a new run ID, because evidence is retained.

## Helpers

- `helpers/control`: executable launcher, doctor, AX dispatcher and cleanup. Invocation: `"$C" <launch|doctor|snapshot|duration|integrations|desktop-hooks|menu|press|set|type|cleanup> "$RUN"` plus the arguments shown above.
- `helpers/integration-fixture`: executable local JSON socket server used by `control launch`; its invocation is `helpers/integration-fixture <owned-socket> <evidence-directory>`. Use `control` for ownership tracking and cleanup.
- `helpers/herdr-fixture`: executable, isolated snapshot/status boundary; `"$PWD/.cursor/skills/verify-dynamic-agents/helpers/herdr-fixture" api snapshot` prints its fixed fixture.
- `helpers/launch.swift`: launched by `control` through `swift helpers/launch.swift <owned-app-path>`; opens the exact isolated bundle and prints its PID.
- `helpers/ax.swift`: compiled by `control launch`; invoke through `control` so PID and bundle checks are enforced.

For native-only and real-herdr journeys, follow [live-activity.md](features/live-activity.md) and [terminal-focus.md](features/terminal-focus.md). They have additional prerequisites and open real terminal views; use the authorization already present in the conversation, and ask only when a proposed real-session action exceeds that scope.
