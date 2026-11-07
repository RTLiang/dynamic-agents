# Desktop client hooks

Users enable local coding-client lifecycle reports without running the session inside herdr.

## Sub-features

- `desktop-install-remove`: install/remove managed entries for Claude Code, Codex, Cursor and shared-runtime Copilot while preserving other hooks.
- `desktop-update`: distinguish missing hooks from a shared helper whose content differs, replace it with the app's bundled helper and refresh every installed adapter.
- `desktop-consistency`: detect a packaged app, checkout or installed helper mismatch before changing a real installation.
- `desktop-events`: prompt/working, completion, interruption and session end drive the dashboard and activity filter.
- `desktop-host`: activate the observed host app, without guessing that an open client is busy.

## How to get to it (user POV)

- Connection Settings → Agent Integrations → Manage Integrations → Desktop Clients.
- Install a hook, restart that client, review hook trust where required and start a new coding task.
- Click the corresponding dashboard or activity row to open its host app.

## Driving it with AX

Preconditions: unlocked macOS session and a new isolated `control launch` run. The launch scopes desktop data and client configuration to its scratch directory. Normal user hook files are not used.

- `"$C" desktop-hooks "$RUN" | tee "$E/desktop-hooks.txt"` opens the Desktop Clients tab, installs all four adapters, appends a harmless difference marker to its owned helper, refreshes through `desktop-hooks-refresh`, requires both Update and Remove for Codex, updates the shared helper and requires every Update button to disappear before removing the adapters. Require the transcript's state checks, `PASS: desktop-hooks` and `hook-consistency-after.json` with `passed: true`.
- Preserve the automatic AX snapshots `desktop-before-install.json`, `desktop-update-available.json`, `desktop-after-update.json` and `desktop-after-remove.json`; they pair the actions with visible state.
- Inspect the isolated scratch `config` files and backup files before cleanup; only managed entries should be removed. The bridge `desktop-data/sources.json` must show removed sources disabled.
- Capture the resulting AX tree using `"$C" snapshot "$RUN" > "$E/desktop-after.json"`, then run the normal cleanup and confirm the evidence remains.
- Run `python3 scripts/test-desktop-hooks.py` for real script/config and report transitions. The script uses disposable directories and Trash cleanup.
- For a real installed App, run `"$PWD/.cursor/skills/verify-dynamic-agents/helpers/hook-doctor" /Applications/DynamicAgents.app > "$E/installed-hook-doctor.json"` before considering its Update action. A mismatch is a failed consistency check; retain the exit code and report it independently of an isolated pass.
- Follow [codex-background-sessions.md](codex-background-sessions.md) for the real dashboard path from controlled Codex memory input.
- For vendor smoke tests, use an actual supported client and verify its event files, host attribution and resulting rows through user actions; record the client/runtime version and hook trust. Apply the session's existing authorization; request permission only for changes outside that scope.

## Gotchas

- The Update prompt currently means content differs; it does not prove the installed helper is older. An old App can offer to replace a newer script with its own older copy. The read-only consistency doctor must expose this case, and an isolated newly built App does not resolve the real installation's mismatch.
- Locking the screen blocks AX driving. The doctor reports this condition; do not report the UI journey as passed.
- The fixture proves settings and file boundaries, not that a vendor loaded or trusted the hook. Ordinary Claude/ChatGPT chat, remote sessions and VS Code's legacy Local runtime are different surfaces.
- Hooks inside herdr deliberately do nothing to avoid duplicate sessions; use herdr's own integration journey there.
- Unknown host ancestry keeps working state Unknown. App presence alone is not evidence of a running task.
- Opening the host app does not select an exact conversation or editor window.
