# Dynamic Agents

[English](README.md) · [简体中文](README.zh-CN.md)

Keep an eye on your coding agents without watching every terminal.

Dynamic Agents is a native Mac app that shows which coding conversations are running, waiting for you, or ready to review. A system Live Activity lets you return to a session from the menu bar area.

**[Download the latest release](https://github.com/RTLiang/dynamic-agents/releases/latest)**

## Requirements

- An Apple silicon Mac running **macOS 27.3 or later** for the app with Live Activities.
- [herdr](https://herdr.dev/) for sessions running inside herdr.
- Python 3 and a supported client's lifecycle hooks for desktop sessions outside herdr. You can use this mode without running herdr.

Desktop adapters support Claude Code, Codex App / CLI, Cursor Agent, and VS Code's shared Copilot runtime. Client versions, organization policies, and hook trust settings determine whether events are delivered. Ordinary chat windows are not monitored.

## Install

1. Download the ZIP from the [Releases page](https://github.com/RTLiang/dynamic-agents/releases/latest), unzip it, and move **DynamicAgents.app** to **Applications**.
2. Open the app. If macOS blocks it, open **System Settings → Privacy & Security**, find the message about Dynamic Agents, and choose **Open Anyway**, then confirm. Use the release's SHA-256 file if you want to check the download.
3. When you use terminal navigation, enable **Dynamic Agents** in **Privacy & Security → Accessibility** and allow its Automation request for your terminal.

Releases are built locally. They do not use an Apple Developer ID certificate or notarization. Apple silicon binaries retain the local ad-hoc signature required to run; this is not Apple verification. First-launch approval, Accessibility, and Automation are separate macOS controls.

## Start monitoring

**Sessions inside herdr**

Start herdr, run your coding agent inside it, then open Dynamic Agents. The app discovers local herdr clients automatically. Use the gear button to choose a session or a specific terminal window when you have more than one.

**Desktop clients and sessions outside herdr**

Open **Connection Settings → Agent Integrations → Manage Integrations → Desktop Clients**. Install the adapter you need, restart that client, and review its hook permissions. Codex requires trusting the hooks in its own hook settings. Existing client hooks are preserved.

## Understand the list

The default order is **Running → Needs Input → Completed → Idle**, followed by Unknown when a connection cannot be verified. You can search, filter by status, or sort the table yourself.

| Status | What it means |
| --- | --- |
| **Running** | The agent is actively working on a turn. |
| **Needs Input** | Work is paused for a permission, answer, or decision from you. |
| **Completed** | A turn ended recently and its result is ready to review. This does not mean an entire project is finished or that every requested outcome succeeded. |
| **Idle** | The coding session is still available, with no work running and no current completion reminder. A new or interrupted session can also be idle. |
| **Unknown** | The app cannot currently verify the session's state. It is not counted as running. |

A completion reminder lasts **10 minutes by default**. Change **Show Completed For** in Connection Settings from **1 to 1440 minutes**. Viewing a result does not restart its timer. When the reminder expires, an available session becomes Idle; a closed desktop session disappears.

The app lists coding sessions and recent completions. Empty shell tabs, closed idle desktop sessions, ordinary chat, and internal work such as Codex memory consolidation or title generation do not belong in the list.

## Return to your work

Double-click a row, select it and press **Return**, or choose a session from the menu bar or Live Activity.

For herdr, Dynamic Agents selects the existing page in your chosen terminal client. It keeps other clients on their current pages and does not create another window or tab. Supported terminals are **Ghostty 1.3+**, **iTerm2**, and **Apple Terminal**. Keep herdr's normal sidebar visible and mouse capture enabled for direct navigation; unsupported or ambiguous layouts produce an explanation rather than choosing another client.

For general desktop clients, the app opens the observed host app. It cannot select an exact conversation inside every editor.

## Live Activities and language

Live Activities show **running sessions and recent completions**. Idle sessions and sessions waiting for input stay in the dashboard and menu. When no eligible session remains, the activity hides while monitoring continues.

The app and Live Activity support **English and Simplified Chinese**. They follow your Mac's language or the language selected for Dynamic Agents in **System Settings → General → Language & Region → Applications**. Compact counts, expanded statuses, action hints, and accessibility text use that language. Your session titles and project names stay as you named them.

You can hide the menu bar icon in settings without stopping monitoring. Closing the dashboard also keeps monitoring running. Reopen the app from the Dock to restore its window or icon.

## If something does not appear or open

- **No sessions:** check that herdr is running, or that the desktop adapter is installed and trusted. Start a new coding turn so the client sends an event.
- **Wrong herdr window:** select the exact **Open With** app and **herdr Window** in Connection Settings. A closed selected window must be selected again; the app will not redirect you elsewhere.
- **Navigation stopped after an update:** open Accessibility settings. If the existing Dynamic Agents entry is enabled but no longer works, remove that entry and add the current app from Applications again. Complete password or Touch ID prompts yourself.
- **Hook says Update Available:** use the current app release to update the adapter. Keep the app and copied helper from the same version; an older app cannot tell that a separately replaced script is newer.
- **Live Activity missing:** enable it in the app, allow it if macOS asks, and check that a session is running or recently completed.

## Privacy and updates

Session status stays on your Mac. Desktop hooks store lifecycle metadata, a hashed session identifier, a project basename, and process ancestry. They do not save prompts, tool arguments, or transcripts. Codex source classification reads only a bounded session-metadata header.

The optional update check contacts this repository's public GitHub Releases API. It opens the release page; it does not install updates automatically or upload your session content. You can disable automatic checks in settings.

## Build or contribute

For local builds, release packaging, and verification, see [the release guide](docs/RELEASES.md), [desktop hook details](docs/DESKTOP-HOOKS.md), and [the verification skill](.cursor/skills/verify-dynamic-agents/SKILL.md). CI checks the code; release packages are compiled and uploaded from a local Mac.
