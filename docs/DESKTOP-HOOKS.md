# Agent lifecycle hooks

Lifecycle reports are the sole monitoring input. Supported sources are Pi, Claude Code, Codex App / CLI, Cursor and VS Code Copilot. Client hook support, enterprise policy, reload requirements and trust settings determine whether events reach the helper.

## Installation

Open **Settings → Agent Hooks → Manage Agent Hooks**. Install the chosen adapters, restart or reload each client and approve its hooks when required. Pi installs a copied TypeScript extension in its settings file; use **/reload**. Its API must support agent_settled. Codex requires reviewing hook definitions. Installation and removal apply immediately, independent of the enclosing settings Save/Cancel.

The Python installer uses private atomic files, backups and a lock, rejects malformed/symlinked configuration, and preserves unrelated hooks/extensions. It owns only its exact managed commands and Pi extension path. Update availability compares bundled helper contents. Updating one adapter refreshes all displayed states for the shared helper. Pi additionally compares its copied TypeScript resource.

## Reports and host identity

Reports contain metadata only: hashed identity, source, state, event time/sequence, project basename, optional bounded title, ancestor PIDs, optional runtime PID and a recognized host-App hint. Sparse events preserve the previous project. Reports older than one day and disabled sources are excluded. There is no multiplexer detection or alternate polling input.

Host resolution prefers the nearest regular App in the observed ancestry, validated against process start time. Detached CLI processes may use a recognized bundle hint from __CFBundleIdentifier or TERM_PROGRAM; this identifies an App, not a terminal client or window. Duplicate App matches, unknown hints and restarted identities fail safely. A missing App does not stop monitoring a separately verified live Pi/Codex runtime. Opening activates the existing host process and issues no keyboard, mouse, window, tab or conversation command.

Pi reports running on agent_start and completion on agent_settled. Waiting, cancellation, errors, session switch and shutdown have distinct transitions. Final settlement avoids false completion during retries. The extension reads session metadata and runtime PID, not messages or transcripts.

Codex runtime validation checks the observed executable, process start time and parent chain. App branding is recognized by bundle identity. Saved user titles come from a bounded title index and affect presentation only.

## Codex background work

The reporter reads only a bounded, matching first session_meta line from a regular, current-user-owned rollout file opened without following symlinks. Structured internal/subagent sources, memory consolidation, memgen and non-user thread sources are excluded. Persisted classification prevents sparse events reviving these records. Parent IDs are protected and legacy matching records are suppressed. Ordinary titles/projects containing “memory” remain valid. Missing metadata preserves previous behavior; arbitrary future internal formats are not promised.

## Verification

Python tests exercise five installers, ownership, backups, reporting, malformed configuration and removal. The Pi Node journey loads the actual copied extension and crosses the Python reporter boundary. Swift tests cover host identity, detached runtimes, PID reuse, retention, titles, handoff and bounded payloads. The [UI skill](../.cursor/skills/verify-dynamic-agents/SKILL.md) covers five-adapter install/update/remove, memory filtering, default row order and activation of an owned two-window host. Controlled events establish these boundaries, not a vendor's scheduling or hook trust.
