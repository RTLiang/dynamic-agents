---
name: verify-dynamic-agents
description: Verify Dynamic Agents' macOS UI, desktop hook consistency and Codex background-session filtering, terminal handoff, and Live Activities through user-facing journeys.
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
"$C" desktop-memory "$RUN" | tee "$E/desktop-memory.txt"
"$C" snapshot "$RUN" > "$E/after.json"
"$C" cleanup "$RUN" | tee "$E/cleanup.txt"
trap - EXIT
rg -q '^PASS: desktop-memory$' "$E/desktop-memory.txt"
for artifact in doctor.txt desktop-memory-inputs.json desktop-memory-records.json desktop-memory-dashboard.json desktop-memory-removed.json desktop-config-after.json hook-consistency-after.json cleanup.txt; do
  test -s "$E/$artifact"
done
test ! -e "$PWD/.build/verify-dynamic-agents/$RUN"
test ! -S "/tmp/dav-$RUN.sock"
echo "Evidence retained: $E"
```

`launch` builds the actual SwiftPM Companion in debug mode, packages a disposable app with a unique bundle identifier, removes its URL registration, signs it ad hoc, launches its executable and waits for the connected `agents-table` with both fixture rows. A standalone app process or build success alone is not ready. The fixture implements the production herdr CLI boundary, accepting explicit `--session default` followed by `api snapshot` and `status --json`; an owned local socket fixture handles `integration.list`, `integration.install` and `integration.uninstall`. It cannot prove actual herdr discovery, focusing or native ActivityKit. `HERDR_BIN` and the fixture trace are scoped to that process. The isolated preferences domain starts empty; launch arguments disable automatic update checks. Desktop hook data and client configuration are scoped to scratch via process-local environment overrides. The app launches through NSWorkspace with its owned bundle ID; real client settings are not read or installed by the fixture. The user's installed App, its settings and actual herdr session are not reused; the test can still bring its own window to the foreground. SwiftPM build output is shared, so avoid simultaneous builds in the same checkout.

## Doctor

Run `"$C" doctor "$RUN"` whenever anything looks wrong. It validates the recorded PID's executable path and bundle ID, Accessibility authorization, the table, a connected fixture and both expected rows. It also reports app version/build and compares the bundled hook resource with the checkout and any installed helper in the owned data directory. A missing Accessibility grant, locked screen or absent GUI session is a failed precondition: report it instead of changing permissions or unlocking the system. Check `$E/build.log`, `$E/ax-build.log`, `$E/app-launch.log` and `$E/herdr-commands.log` for diagnostics. Never drive an unrelated PID.

For an installed App's misleading Hook Update prompt, run this separate read-only check before touching its Update button:

```bash
"$PWD/.cursor/skills/verify-dynamic-agents/helpers/hook-doctor" /Applications/DynamicAgents.app > "$E/installed-hook-doctor.json"
```

An exit code of 1 with `bundledMatchesCheckout: false` or `installedMatchesBundle: false` records a real mismatch. Content inequality does not establish which script is newer. Report the installed-app failure independently of the isolated Companion result; an isolated pass cannot clear it. This check reads bundle metadata and script bytes without running the installed script or changing hooks. It does not establish a vendor's hook trust or live event delivery.

## Drive

Use the feature map for exact journeys and remaining manual/exclusive paths. Helpers operate on the isolated PID only:

```bash
"$C" snapshot "$RUN" > "$E/dashboard.json"
"$C" press "$RUN" AXButton 'Connection Settings'
"$C" set "$RUN" completion-window-minutes 7
"$C" press "$RUN" AXButton Cancel
"$C" menu "$RUN"
```

`press` matches an AX role and exact English title, description or help. `set` writes AXValue by accessibility identifier; `role:AXTextField` selects the first matching role. `type "$RUN" AXTextField Build` focuses the field and sends keyboard events to the verification PID, selecting existing text first; pass `''` to clear. Use `type`, not `set`, for the search field: AXValue alone does not trigger SwiftUI search updates. `duration` is a complete save/reopen/cancel user journey that checks the isolated persisted preference. `integrations` exercises list/install/update/remove through the real management UI and the owned socket fixture; see [features/integrations.md](features/integrations.md). `desktop-hooks` exercises the four desktop adapters' install/update/remove UI against isolated client configurations and captures the update prompt disappearing after shared-helper replacement. `desktop-memory` installs Codex from that UI, feeds controlled lifecycle events through the copied production hook, checks that the dashboard retains one ordinary completed memory-project session and excludes two background memory sessions, then removes Codex through the UI and checks the dashboard returns to baseline. See [features/desktop-hooks.md](features/desktop-hooks.md) and [features/codex-background-sessions.md](features/codex-background-sessions.md). `menu` reads the app's status item. `snapshot` emits the AX tree as JSON; it can include sensitive session names if a non-fixture app is ever substituted.

## Evidence

Keep proof under `$E`, which is inside ignored `.build/`. Capture each action and observed result, AX snapshots before/after, and the persisted side effect for changes. `duration.txt` shows open, enter, Save, reopen, Cancel and the saved value; `herdr-commands.log` must contain only `--session default api snapshot` and `--session default status --json`; status is also queried for precise terminal discovery. For that feature also inspect `integration-actions.jsonl` and `integration-state.json` to verify mutations; merely opening the manager must not install anything. Check it, rather than assuming a dry run is harmless. For desktop journeys retain their action transcript, automatic AX snapshots, `hook-consistency-after.json` and `desktop-config-after.json`; the latter preserves the owned configurations and confirms the removed sources are disabled before scratch cleanup. The memory journey also writes `desktop-memory-inputs.json` and `desktop-memory-records.json`; compare the three delivered sessions with the dashboard's three total rows (the two herdr fixtures plus one user completion). After UI removal there must be two rows again. The controlled Codex event source replaces the external vendor only at the existing lifecycle-hook boundary. This proves the copied hook, file collector and real dashboard together; actual Codex memory scheduling, vendor hook trust, runtime host attribution, native island counts and clicks remain separate journeys. A failed installed-app consistency doctor stays failed even when this isolated path passes.

Screenshots require Screen Recording authorization and may contain private data; use existing grants and report unavailable capture separately. AX trees and successful chronod reloads are not system-island screenshots. Keep local screenshots, logs, paths and real session data under ignored evidence.

## Cleanup

`"$C" cleanup "$RUN"` terminates only the recorded matching verification executable and owned integration-fixture server, removes its unique preferences domain and moves scratch state and the owned socket to Trash. It refuses a reused PID, an unresponsive process or symlinked scratch path. Evidence survives at `$E`; confirm it still exists. Never kill by process name or clean another instance. Run cleanup after each failed iteration; use a new run ID, because evidence is retained.

## Helpers

- `helpers/control`: executable launcher, doctor, AX dispatcher and cleanup. Invocation: `"$C" <launch|doctor|snapshot|duration|integrations|desktop-hooks|desktop-memory|menu|press|set|type|cleanup> "$RUN"` plus the arguments shown above.
- `helpers/hook-doctor`: executable read-only bundle/checkout/helper comparison. Invocation: `helpers/hook-doctor /Applications/DynamicAgents.app`; for scratch use `helpers/hook-doctor "$PWD/.build/verify-dynamic-agents/$RUN/DynamicAgents.app" --data-dir "$PWD/.build/verify-dynamic-agents/$RUN/desktop-data"`.
- `helpers/desktop-fixture`: executable Codex lifecycle input fixture. Invocation: `helpers/desktop-fixture "$RUN"`, after the UI has installed Codex into that owned run. `control desktop-memory` invokes it between UI installation and dashboard assertions.
- `helpers/integration-fixture`: executable local JSON socket server used by `control launch`; its invocation is `helpers/integration-fixture <owned-socket> <evidence-directory>`. Use `control` for ownership tracking and cleanup.
- `helpers/herdr-fixture`: executable, isolated snapshot/status boundary; `"$PWD/.cursor/skills/verify-dynamic-agents/helpers/herdr-fixture" api snapshot` prints its fixed fixture.
- `helpers/launch.swift`: launched by `control` through `swift helpers/launch.swift <owned-app-path>`; opens the exact isolated bundle and prints its PID.
- `helpers/ax.swift`: compiled by `control launch`; invoke through `control` so PID and bundle checks are enforced.

For native-only and real-herdr journeys, follow [live-activity.md](features/live-activity.md) and [terminal-focus.md](features/terminal-focus.md). They have additional prerequisites and open real terminal views; use the authorization already present in the conversation, and ask only when a proposed real-session action exceeds that scope.

Use `/maintain-verification-skill` when app entry points or behavior change, so the feature map and executable journeys stay aligned.
