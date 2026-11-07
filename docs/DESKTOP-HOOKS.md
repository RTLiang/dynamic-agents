# Desktop coding-agent hooks

Dynamic Agents has two independent monitoring inputs: herdr panes, and local lifecycle reports from supported desktop coding clients or IDE runtimes. Installing a herdr integration alone does not observe a desktop app outside herdr.

## Supported local hook formats

| Client/runtime | Hook configuration | Events used |
| --- | --- | --- |
| Claude Code Desktop and Claude Code CLI | User Claude settings hooks | Session start/end, prompt submit, tool activity, permission request, stop and stop failure |
| Codex App and local Codex CLI | User Codex lifecycle hooks | Session start/end, prompt submit, tool activity, permission request, stop and interrupt |
| Cursor Agent Chat | User Cursor hooks | Session start/end, prompt submission, agent thought and stop |
| VS Code's shared Copilot runtime | User Copilot hook file | Session start/end, prompt submit, successful tool use and agent stop |

These are coding-agent sessions, not ordinary Claude/ChatGPT chat windows, all editor activity, or remote/cloud sessions. VS Code's legacy Local hook parser is a different surface; its settings are not configured by the shared-runtime installer. Managed policies, runtime versions, hook-disable settings and remote execution can prevent reports.

Official contracts:

- [Claude Code hooks](https://code.claude.com/docs/en/hooks): hooks are available in terminal, IDE and Desktop sessions; user settings supply the installed entries.
- [Codex hooks](https://learn.chatgpt.com/docs/hooks): user hooks, event schemas, trust review and Desktop Settings → Hooks. Installation does not bypass required user review or trust.
- [Cursor hooks](https://cursor.com/docs/hooks): user hooks, Agent Chat lifecycle and the stop status. A cancelled/error stop is not counted as successful completion.
- [VS Code shared-runtime hooks](https://code.visualstudio.com/docs/agent-customization/hooks) and [Copilot's schema](https://docs.github.com/en/copilot/reference/hooks-reference): shared user hook locations and camelCase event payloads.

## Setup

Open **Connection Settings → Agent Integrations → Manage Integrations → Desktop Clients**. Install the desired hook, restart that client and review any hook permissions. Codex requires trusting the new definitions in its hook settings. Install/remove applies immediately, independently of the enclosing settings Save/Cancel. Existing user hooks and herdr entries are preserved, and a local backup is made before rewriting a configuration file. Unsupported or invalid JSON is rejected rather than overwritten.

The bridge script is copied to the application's user data directory, so updating the app does not invalidate its hook command. Removing the managed hook removes only its entries and disables that source's old reports; it does not delete unrelated settings or backups. Hooks are not installed automatically when the app launches.

## Reporting and host identity

The Python bridge writes atomic, private local metadata records; it stores only a hashed session identifier, source, state, event sequence/time, project basename and ancestor process IDs. It does not store prompt text, tool arguments/results, transcripts or full working-directory paths. Reports are inactive inside herdr to avoid duplicate sessions.

The app combines reports with running-app ancestry and launch dates. A running app by itself never creates a working session. A working event with no verifiable host is displayed as Unknown and excluded from working island counts; a completed event carries its actual reported time. Interrupted or failed events are not converted into successful completion. Events from subagents are excluded from the root-session count.

The existing configurable completion window applies to both inputs. Local hook sessions can remain visible when herdr is disconnected. Clicking a hook session in a supported terminal resolves its live ancestor PID and TTY, checks process creation time and app ancestry, then selects that exact terminal surface. General desktop editors activate the observed host app; a particular editor conversation is not selected. This route never issues public herdr focus commands. Closed hosts stop contributing unverified working state. Stale files older than one day are excluded.

Hooks observe the runtime's event contract. Stop events may precede another hook's decision to continue a turn; subsequent activity updates correct the state. These hooks are not permission policy: they do not approve tools or bypass sandbox controls. Cursor's prompt hook returns the documented continue result; permission/tool hooks are not installed for Cursor.

## Verification

Run:

```bash
python3 scripts/test-desktop-hooks.py
python3 scripts/check-localizations.py
HERDR_LIVE_TEST=1 swift test --build-system native
```

Python tests exercise all four installers against disposable configurations, preserve existing hooks, check metadata-only reporting, exclude herdr/subagents, reject invalid JSON and verify removal. Swift tests cover host mapping, unknown/expired events, reported completion time, configurable filtering and compatibility with herdr identities. These validate the adapters and file boundary; they do not replace a per-vendor application smoke test.

The project verification skill maps the desktop settings UI and local event fixture separately. A locked macOS GUI is an unmet precondition for UI driving, not a passing result. Before claiming a vendor integration is live, start a new task in that actual client, observe its prompt/stop/interruption events, verify the host identity and test opening it from the app/island. System Widget presentation and a mouse click require separate native verification.
