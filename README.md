# Dynamic Agents

[English](README.md) · [简体中文](README.zh-CN.md)

Follow your coding agents from a native Mac dashboard and system Live Activity.

**[Download the latest DMG](https://github.com/RTLiang/dynamic-agents/releases/latest)**

Dynamic Agents receives lifecycle events from **Pi, Claude Code, Codex App / CLI, Cursor and VS Code Copilot**. It shows working sessions and recent completions. Clicking a session activates its host App.

## Requirements and installation

- Apple silicon, **macOS 27.3+**, and Python 3.
- A supported agent with lifecycle hooks enabled. Pi requires the extension API with the agent_settled event. Vendor versions, policies and hook trust determine event delivery.

1. Download the DMG, open it, and drag **DynamicAgents.app** onto **Applications**. Eject the disk image and launch the installed app.
2. If macOS blocks first launch, use **System Settings → Privacy & Security → Open Anyway** and confirm. Releases use the required local ad-hoc execution signature, without Developer ID signing or notarization.
3. Open **Settings → Agent Hooks → Manage Agent Hooks**, then install the adapters you use. Restart the client or reload its extensions. In Pi use **/reload**; in Codex review and trust the new hook definitions.
4. Start a coding turn so the agent sends its first event. Existing installations showing **Update Available** should update the shared helper from this release.

Hook installation preserves unrelated configuration and creates local backups. Install/remove applies immediately. App activation needs no Accessibility or Automation permission.

## Session states

The default order is **Working → Completed → Idle → Unknown**. Search, filter or sort the table to find a session.

| State | Meaning |
| --- | --- |
| Working | The current turn is still in progress, including pauses for permissions or answers. |
| Completed | A turn ended recently. This describes a turn boundary, not project completion or a guarantee of success. |
| Idle | The session is available without active work or a current completion reminder. |
| Unknown | Current work cannot be verified; it is not counted as Working. |

Completion reminders last **10 minutes** by default. Change **Show Completed For** in Settings from **1–1440 minutes**. Viewing a result keeps the original timer. After expiry, available sessions become Idle and closed sessions disappear. Interrupted Pi runs become Idle; failed runs do not create a completion reminder. Codex requires verified user-session metadata. Internal memory/title/subagent work and sessions with unavailable metadata are excluded, including ephemeral workers without a rollout. User-created ephemeral sessions without verifiable metadata are also excluded.

## Open the host App

Double-click a row, press Return on the selection, or click a session in the menu or Live Activity. Dynamic Agents activates the already running host App. Its existing window, tab and conversation selection stays with that App.

The host is resolved from process ancestry. For detached CLI processes, a recognized App hint from the hook environment can identify the terminal App; it cannot identify a particular client inside a multiplexer. Ambiguous or unavailable hosts produce an error. A verified live CLI can still be monitored without a known host.

## Live Activities and language

Live Activities show **working sessions and recent completions**. Idle sessions remain in the dashboard and menu. With no eligible sessions, the activity hides and monitoring continues. Hiding the menu icon or closing the dashboard also keeps monitoring active. Compact English labels use **2 Work / 1 Done**; full status labels use **Working / Completed**.

The app and Widget support **English and Simplified Chinese**, following the system or the app language chosen in **System Settings → General → Language & Region → Applications**. Session names and project names retain their original text.

## Privacy and updates

Local reports contain a hashed session ID, status, project basename, bounded session title, timestamps, process ancestry and optional host App hint. They exclude prompts, tool arguments/results and full working-directory paths. Codex classification reads a bounded first session-metadata line; saved titles come from the bounded session-title index.

The optional update check contacts this repository's public GitHub Releases API and opens the release page. It uploads no session data and installs nothing automatically. **When upgrading from 0.1.x, download the DMG manually:** those versions recognize ZIP assets only.

If sessions are missing, check adapter installation and trust, reload the client, and start another turn. If opening fails, check the host is still running and issue a fresh lifecycle event. For a missing Live Activity, enable it in Settings and check for a working or recently completed session.

## Development

See [release packaging](docs/RELEASES.md), [hook details](docs/DESKTOP-HOOKS.md), and [UI verification](.cursor/skills/verify-dynamic-agents/SKILL.md). CI checks code; DMGs are built and uploaded locally.
