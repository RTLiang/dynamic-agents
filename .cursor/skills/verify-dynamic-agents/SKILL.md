---
name: verify-dynamic-agents
description: Verify Dynamic Agents UI, lifecycle adapters, app activation, completion reminders and native Live Activities through user-facing journeys.
---

Read [features/README.md](features/README.md), then the feature files relevant to the change. Distinguish model tests, controlled lifecycle events, direct actions and physical system Widget clicks in the report.

## Isolated UI journey

Use macOS 15+, Swift/Xcode tools, Python 3, codesign, trash and an unlocked GUI session. The verification process needs Accessibility permission; the product does not. The harness checks permission and never changes it.

Set C to this directory's helpers/control absolute path and choose a fresh lowercase alphanumeric RUN of at most 32 characters. Run:

1. "$C" launch "$RUN" — builds the production SwiftPM Companion and a small two-window host App, packages unique owned bundles, isolates defaults/data/client settings, and checks the empty dashboard and host state. Ready requires the live table and host, not merely a launched PID.
2. "$C" hooks "$RUN" — installs all five adapters through the real UI, makes the shared helper outdated, updates it through the UI, and requires all update prompts clear. The owned host emits production lifecycle reports; the Codex producer exercises normal and background metadata. Require ordered Running/Completed/Idle rows, no background rows, exact host PID activation, retained host window selection/count, five UI removals and an empty dashboard.
3. "$C" settings "$RUN" — edits completion retention, saves, reopens, checks the persisted value and cancels.
4. "$C" snapshot "$RUN" — optional current AX tree. "$C" press "$RUN" <role> <label> presses only an owned App control.
5. "$C" cleanup "$RUN" — stops only processes with the recorded owned executable paths, clears only owned defaults, and moves scratch to Trash. Keep an EXIT trap around the journey so failed runs are cleaned.

VERIFY_LANGUAGE=zh-Hans on launch runs the same journeys in Simplified Chinese; the default is English. Keep builds in the same checkout sequential. Desktop configuration and hook data use process-local overrides; actual client settings and the installed App are not reused. Hooks can bring the fixture windows forward.

## Evidence and diagnostics

Scratch is .build/verify-dynamic-agents/<run>; retained evidence is .build/verify-dynamic-agents-evidence/<run>. Capture action stdout/stderr as well as automatic AX and host-state JSON. Keep real titles, paths, process IDs and configuration fingerprints in these ignored directories.

Use "$C" doctor "$RUN" only before adding reports; it requires the empty starting dashboard. helpers/hook-doctor <App> [--data-dir <owned-data>] compares checkout, bundle and installed Python/Pi resources without modifying them. An installed-app mismatch remains a failure even when an isolated journey passes.

A locked screen, absent GUI or missing probe authorization is a failed precondition. Report it, preserve evidence and clean owned resources. User credentials stay with the user.

## Evidence boundary

Controlled lifecycle events prove the copied helper, collector, dashboard and host activation together. They do not prove external vendor scheduling/trust, actual terminal contents or native Widget presentation. The Companion has no Widget. Follow [live-activity.md](features/live-activity.md) for ActivityKit and physical system-row journeys. Use the authorization already present in the task when installing; do not reset system permissions or drive unrelated windows.
