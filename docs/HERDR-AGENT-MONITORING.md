# herdr Agent Monitoring and Hook Integration

## Scope and sources

This investigation pins implementation claims to herdr **v0.9.5**, commit `2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01`. Official web documentation can change independently of that release.

- [Agent detection source](https://github.com/herdrdev/herdr/blob/v0.9.5/src/detect/mod.rs)
- [Official agents](https://herdr.dev/docs/agents/)
- [Official integrations](https://herdr.dev/docs/integrations/)
- [Adding an agent's own reporting](https://herdr.dev/docs/add-herdr-support/)
- [Integration API schema](https://github.com/herdrdev/herdr/blob/v0.9.5/src/api/schema/integrations.rs)
- [Integration API implementation](https://github.com/herdrdev/herdr/blob/v0.9.5/src/app/api/integrations.rs)

## How herdr monitors agents

herdr combines process identity with live terminal-buffer rules, OSC information and PTY activity. Reading arbitrary screen text from another terminal is not the contract: herdr owns its panes. Full lifecycle reporters can replace screen-derived state; agents without reliable lifecycle events retain herdr detection. A running process alone does not establish that a turn is working. See the [detector](https://github.com/herdrdev/herdr/blob/v0.9.5/src/detect/mod.rs) and [terminal state arbitration](https://github.com/herdrdev/herdr/blob/v0.9.5/src/terminal/state.rs).

The source enumerates 24 built-in agent kinds, of which 22 have screen manifests. Supported self-reporting agents can also identify themselves without an upstream binary change; these are not a second fixed list to hardcode. [Official agent documentation](https://herdr.dev/docs/agents/) describes both routes.

## Hook capabilities differ

| Integration group | State authority in v0.9.5 | Integration purpose |
| --- | --- | --- |
| Pi, OMP, MastraCode, OpenCode, Kilo, Kimi | Lifecycle reports when the integration is active | State plus session identity/restore |
| Claude Code, Codex, Copilot, Cursor, Devin, Droid, Qoder, Hermes, Qwen, Grok, Antigravity CLI | herdr detection | Session identity/restore; incomplete hook events are not treated as complete lifecycle coverage |
| Amp, Kiro, Maki, Gemini, Cline and other supported kinds without a managed installer | Detection and/or agent-provided reporting | Follow herdr's agent-specific support |

The first group is explicitly enumerated by `full_lifecycle_hook_authority` in [the detector](https://github.com/herdrdev/herdr/blob/v0.9.5/src/detect/mod.rs). The current [integration documentation](https://herdr.dev/docs/integrations/) explains per-agent limitations. In particular, [Claude's hook](https://github.com/herdrdev/herdr/blob/v0.9.5/src/integration/assets/claude/herdr-agent-state.sh) and [Codex's hook](https://github.com/herdrdev/herdr/blob/v0.9.5/src/integration/assets/codex/herdr-agent-state.sh) accept SessionStart and send `pane.report_agent_session`; neither sends working/idle on every turn.

The [Pi extension](https://github.com/herdrdev/herdr/blob/v0.9.5/src/integration/assets/pi/herdr-agent-state.ts) handles TUI session start, agent start, agent settled and explicit blocked events. Reports are coalesced and sequenced, with short socket timeouts and retry. It gates on herdr's inherited environment. Its supported mode is the pane-local TUI, not arbitrary headless runs.

## Broad coverage in this app

Dynamic Agents now exposes **Connection Settings → Agent Integrations → Manage Integrations**. The list is read from `integration.list`, including labels, installed state and availability; the app does not maintain an install-target whitelist. Buttons invoke `integration.install` or `integration.uninstall` on herdr's local API. Configuration merging and managed-hook ownership remain herdr's responsibility. Installation/update/removal is only performed after a user presses its corresponding button; opening the screen is read-only. Restart the affected agent afterward.

There are **17 targets in the v0.9.5 structured API**. The CLI also supports the experimental Letta installer, giving 18 CLI targets. Letta is intentionally excluded from the structured API and therefore from the app's management list; it can still be monitored if reported/detected. Do not silently invent an API target for it. See [IntegrationTarget](https://github.com/herdrdev/herdr/blob/v0.9.5/src/api/schema/integrations.rs).

The API endpoint is resolved via `herdr status --json` for the configured executable and named session. The app sends bounded, newline-framed JSON over the returned local Unix socket, with deadlines, partial-read/write handling and a response-size limit. It refreshes the list after a mutation, including after an error; a timed-out mutation is not retried automatically because it may already have modified configuration. Unknown future install states remain unknown.

## Outside herdr

The bundled hooks require `HERDR_ENV`, `HERDR_PANE_ID` and `HERDR_SOCKET_PATH`; [herdr's integration contract](https://herdr.dev/docs/add-herdr-support/) explicitly makes them inactive outside herdr. Installing them does not monitor every agent running anywhere on the machine.

Standalone coding-client monitoring is implemented as a separate local lifecycle bridge, independent of herdr's pane API. It uses agent-specific hook adapters and verified host-app ancestry rather than a generic process-as-working heuristic; see [Desktop coding-agent hooks](DESKTOP-HOOKS.md). Ordinary desktop chat windows and remote runtimes without local events are not covered.

## Event-driven follow-up

The app still polls snapshots once per second. [Socket subscriptions](https://herdr.dev/docs/socket-api/#event-subscriptions) support `pane.agent_status_changed` per pane plus lifecycle notifications. A future subscriber can invalidate and refresh the authoritative snapshot, reconnect on disconnect, and reconcile on `events_lost`. Snapshot/event ordering has no common sequence boundary; buffered events cannot be blindly replayed over snapshots. This change adds hook management, not a new event transport for the agent feed.

## Verification

Core tests cover API decoding, unknown targets/states, mutation acknowledgement, endpoint validation and the real Unix-socket request path with fragmented, timed-out and truncated replies. The optional live test reads integration status without installing or removing anything. UI mutations are verified against an isolated fixture; actual installation in each third-party agent is not claimed without starting that agent and observing its reports. Local paths, screenshots and raw runtime reports are kept outside the public source.
