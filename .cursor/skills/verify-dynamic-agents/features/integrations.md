# Agent integrations

Users inspect herdr-managed agent integrations and install, update or remove a hook/plugin using the selected local herdr server.

## Sub-features

- `integrations-list`: show server-reported targets, command availability, installed state and lifecycle-vs-detection capability.
- `integrations-install`: install an uninstalled integration and refresh its status.
- `integrations-update`: update an outdated integration and refresh its status.
- `integrations-remove`: remove an installed integration and refresh its status.
- `integrations-error`: show unsupported API, connection and configuration errors without assuming the operation succeeded or retrying a timed-out mutation.

## How to get to it (user POV)

- Open Connection Settings → Agent Integrations → Manage Integrations.
- Select Install, Update or Remove for an agent; these actions apply immediately, independently of the enclosing settings Save/Cancel.
- Restart the affected agent to load or unload its integration.

## Driving it with AX

Preconditions: use a new isolated `control launch` run; keep the settings connection unchanged. The fixture includes Pi current, Codex not installed and Claude Code outdated, backed by a local test socket; it never touches real agent configuration.

- **Before:** `"$C" snapshot "$RUN" > "$E/before.json"`.
- **Drive:** `"$C" integrations "$RUN" | tee "$E/integrations.txt"` opens settings and the manager, installs Codex, updates Claude Code, removes Codex and asserts each rendered state.
- **After:** `"$C" snapshot "$RUN" > "$E/after.json"`. Require `PASS: agent-integrations` in the action transcript.
- **Side effects:** inspect `$E/integration-actions.jsonl` and `$E/integration-state.json`. Mutations must be exactly install Codex → current, install Claude → current, uninstall Codex → not_installed; requests must be separated by read-only list refreshes. Opening the manager alone must issue no mutation.
- **Cleanup:** `"$C" cleanup "$RUN"` removes only the run's app, socket server, preferences and scratch socket, retaining evidence.

## Gotchas

- A hook can report session identity without reporting full lifecycle state. Claude Code and Codex state still comes from herdr detection in v0.9.5.
- herdr must be running for the real manager; the selected executable's `status --json` resolves the local endpoint.
- The fixture proves the production UI and API request path, not that a vendor's hook fires correctly. Actual installation modifies agent configuration; verify in a dedicated configuration and restart the real agent before claiming lifecycle reporting works.
- Unsaved connection changes disable the manager until saved, preventing edits through the previous connection by mistake.
