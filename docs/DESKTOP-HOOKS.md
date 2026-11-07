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
- [Codex session name index](https://github.com/openai/codex/blob/main/codex-rs/rollout/src/session_index.rs): append-only thread names; the latest recorded name takes precedence.
- [Cursor hooks](https://cursor.com/docs/hooks): user hooks, Agent Chat lifecycle and the stop status. A cancelled/error stop is not counted as successful completion.
- [VS Code shared-runtime hooks](https://code.visualstudio.com/docs/agent-customization/hooks) and [Copilot's schema](https://docs.github.com/en/copilot/reference/hooks-reference): shared user hook locations and camelCase event payloads.

## Setup

Open **Connection Settings → Agent Integrations → Manage Integrations → Desktop Clients**. Install the desired hook, restart that client and review any hook permissions. Codex requires trusting the new definitions in its hook settings. Install/remove applies immediately, independently of the enclosing settings Save/Cancel. Existing user hooks and herdr entries are preserved, and a local backup is made before rewriting a configuration file. Unsupported or invalid JSON is rejected rather than overwritten.

The bridge script is copied to the application's user data directory, so updating the app does not invalidate its hook command. Configured hooks with an older helper appear as Update Available with an Update action. Updating one adapter refreshes the shared helper and reloads all adapter states; it is distinct from an uninstalled hook. Removing the managed hook removes only its entries and disables that source's old reports; it does not delete unrelated settings or backups. Hooks are not installed automatically when the app launches.

## Reporting and host identity

The Python bridge writes atomic, private local metadata records; it stores only a hashed session identifier, source, state, event sequence/time, project basename, ancestor process IDs and, when available, a Codex session classification (`user` or `background`). It does not store prompt text, tool arguments/results, transcripts or full working-directory paths. Reports are inactive inside herdr to avoid duplicate sessions. Cursor project labels read the documented `workspace_roots` array, including multiple root basenames. Lifecycle events that omit directory metadata retain the previous reported project; an explicit new directory replaces it. Full root paths remain excluded from stored reports.

Codex background threads can emit lifecycle hooks without an `agent_id`. The bridge reads only the first `session_meta` record from the hook's `transcript_path`, bounded to 256 KiB, and checks that its thread ID matches the hook session before using `source` and `thread_source`. Internal sessions, subagents and non-user thread sources are excluded, including memory consolidation, memory generation, title generation and approval review. A known background classification remains excluded when later hooks omit metadata. Updating the Codex helper also marks matching legacy background reports as ended, using rollout filenames to match hashed IDs before reading their metadata headers. No later transcript records, instructions or message text are used for classification or saved. Missing, malformed, oversized, symlinked or unavailable headers retain the existing hook behavior; a header for another thread is ignored without changing the parent session. Session titles, prompts and project names containing “memory” do not trigger filtering.

This follows Magpie's distinction between a user turn and a named background purpose, rather than matching conversation text: its [purpose catalog](https://github.com/yetone/magpie/blob/e6cdeac9c681ad0377b0f863af556d4c1d7be2a8/internal/usage/purpose.go) groups `memory_consolidation`, `memgen` and `memory`. Magpie obtains these purposes from [request headers and turn metadata](https://github.com/yetone/magpie/blob/e6cdeac9c681ad0377b0f863af556d4c1d7be2a8/internal/gateway/codex_backend.go); this local hook bridge uses Codex's session metadata because those HTTP headers are not part of the hook input.

The app combines reports with running-app ancestry and launch dates. For Codex, it also captures the reported ancestors’ current process identities, requires a live Codex executable created before the event, and verifies its current parent chain reaches the host. An exited worker, a reused PID or a reparented process cannot establish Running or Needs Input merely because the app remains open. A running app by itself never creates a working session. An event with no verifiable live host is displayed as Unknown and excluded from running island counts; a completed event retains its actual reported time. Interrupted or failed events are not converted into successful completion. Events from subagents are excluded from the root-session count.

Codex App is identified by the stable `com.openai.codex` bundle identifier. Its localized app name or installation filename can differ without changing its client identity. Other observed Codex runtimes are labeled Codex CLI with their host. Named Codex sessions display their saved conversation title. The app reads only `id` and `thread_name` from the local `session_index.jsonl` metadata index, matches the same hashed identifiers as the hook bridge, and honors the latest appended name. Changes to the index invalidate the cache, including conversation renames. The path follows `CODEX_HOME`, or the default Codex directory; isolated verification follows `DYNAMIC_AGENTS_CONFIG_HOME`. Missing, blank, malformed or unavailable titles fall back to `Codex · <short ID>`. Titles change presentation without changing session identity, lifecycle state or focus targets. The project column independently shows the reported working-directory basename. A missing directory is shown as Unknown Project; a basename alone does not identify a full project path.

The existing configurable completion window applies to both inputs. Local hook sessions can remain visible when herdr is disconnected. Clicking a hook session in a supported terminal resolves its live ancestor PID and TTY, checks process creation time and app ancestry, then selects that exact terminal surface. General desktop editors activate the observed host app; a particular editor conversation is not selected. This route never issues public herdr focus commands. Closed hosts stop contributing unverified working state. Stale files older than one day are excluded.

Hooks observe the runtime's event contract. Stop events may precede another hook's decision to continue a turn; subsequent activity updates correct the state. These hooks are not permission policy: they do not approve tools or bypass sandbox controls. Cursor's prompt hook returns the documented continue result; permission/tool hooks are not installed for Cursor.

## Verification

Run:

```bash
python3 scripts/test-desktop-hooks.py
python3 scripts/check-localizations.py
HERDR_LIVE_TEST=1 swift test --build-system native
```

Python tests exercise all four installers against disposable configurations, preserve existing hooks, check metadata-only reporting, exclude herdr/subagents, reject invalid JSON and verify removal. Codex regressions cover memory/internal/subagent sources without `agent_id`, sparse events, legacy report suppression, parent-ID isolation, ordinary sessions whose text mentions memory, bounded header reads, symlinks, FIFOs and unavailable metadata. Swift tests cover stable Codex App identity under renamed branding, Codex CLI distinction, exited/reused/reparented workers, parent chains through login processes, unknown/expired events, independent project labels, reported completion time, configurable filtering and compatibility with herdr identities. Title tests also cover metadata matching, renames, cache invalidation, malformed records, empty names and safe fallback for missing or oversized indexes. These validate the adapters and file boundary; they do not replace a per-vendor application smoke test.

The project verification skill maps the desktop settings UI and local event fixture separately. A locked macOS GUI is an unmet precondition for UI driving, not a passing result. Before claiming a vendor integration is live, start a new task in that actual client, observe its prompt/stop/interruption events, verify the host identity and test opening it from the app/island. System Widget presentation and a mouse click require separate native verification.
