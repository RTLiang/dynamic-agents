# Desktop client hooks

Users enable local coding-client lifecycle reports without running the session inside herdr.

## Sub-features

- `desktop-install-remove`: install/remove managed entries for Claude Code, Codex, Cursor and shared-runtime Copilot while preserving other hooks.
- `desktop-update`: distinguish configured hooks with an older shared helper from missing hooks, update it and refresh every installed adapter.
- `desktop-events`: prompt/working, completion, interruption and session end drive the dashboard and activity filter.
- `desktop-host`: activate the observed host app, without guessing that an open client is busy.

## How to get to it (user POV)

- Connection Settings → Agent Integrations → Manage Integrations → Desktop Clients.
- Install a hook, restart that client, review hook trust where required and start a new coding task.
- Click the corresponding dashboard or activity row to open its host app.

## Driving it with AX

Preconditions: unlocked macOS session and a new isolated `control launch` run. The launch scopes desktop data and client configuration to its scratch directory. Normal user hook files are not used.

- `"$C" desktop-hooks "$RUN" | tee "$E/desktop-hooks.txt"` opens the Desktop Clients tab, installs all four adapters, appends a harmless previous-version marker to its owned helper, refreshes through `desktop-hooks-refresh`, requires both Update and Remove for Codex, updates the shared helper and checks all installed adapters before removing them. Require the transcript's state checks and `PASS: desktop-hooks`.
- Inspect the isolated scratch `config` files and backup files before cleanup; only managed entries should be removed. The bridge `desktop-data/sources.json` must show removed sources disabled.
- Capture the resulting AX tree using `"$C" snapshot "$RUN" > "$E/desktop-after.json"`, then run the normal cleanup and confirm the evidence remains.
- Run `python3 scripts/test-desktop-hooks.py` for real script/config and report transitions. The script uses disposable directories and Trash cleanup.
- For vendor smoke tests, use an actual supported client and verify its event files, host attribution and resulting rows through user actions; record the client/runtime version and hook trust. Request explicit authorization before modifying a real client's configuration.

## Gotchas

- Locking the screen blocks AX driving. The doctor reports this condition; do not report the UI journey as passed.
- The fixture proves settings and file boundaries, not that a vendor loaded or trusted the hook. Ordinary Claude/ChatGPT chat, remote sessions and VS Code's legacy Local runtime are different surfaces.
- Hooks inside herdr deliberately do nothing to avoid duplicate sessions; use herdr's own integration journey there.
- Unknown host ancestry keeps working state Unknown. App presence alone is not evidence of a running task.
- Opening the host app does not select an exact conversation or editor window.
