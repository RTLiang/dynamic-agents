# Terminal focus

Users select an agent and return to the corresponding herdr pane in its hosting terminal without the app briefly coming to the front during a Widget action.

## Sub-features

- `focus-dashboard`: row double-click, Return, context menu and toolbar entry.
- `focus-menu`: choose an agent in the menu bar menu.
- `focus-widget`: choose an expanded Live Activity row via background App Intent.
- `focus-resolution`: automatic detection, ambiguous terminal choice and unavailable-terminal errors.

## How to get to it (user POV)

- Double-click a dashboard row, select it and press Return, or use `Open in Terminal` in its context menu or toolbar.
- Select an agent in the menu bar menu.
- Open the Live Activity and choose an agent row.

## Driving it with AX

Preconditions: a dedicated real local herdr session, at least one tracked agent, a known terminal host and explicit user permission to focus its pane or replace the installed App. The default fixture returns an error for `agent focus` and cannot prove terminal handoff. Avoid a session the user is actively editing.

- **Read-only preflight:** `HERDR_LIVE_TEST=1 swift test --build-system native` exercises real snapshot and terminal discovery, not UI interaction. Record its output without publishing local paths or session titles.
- **Companion focus probe:** with a dedicated session and consent, run `bash scripts/build-app.sh companion` then `bash scripts/verify-terminal.sh`. This creates a separate app process and focuses the currently focused pane; check the report's before/after pane and frontmost terminal. It is not proof of every UI entry point.
- **Native intent probe:** follow the native setup and `--verify-live-activity` command in [live-activity.md](live-activity.md). It directly calls the real intent and records activations; it is not a system Widget click.
- **Full UI proof:** drive each requested dashboard, menu or Widget entry, record the selected pane before/after via `herdr api snapshot`, and the frontmost app via NSWorkspace. For Widget clicks, record the activation sequence and require no Dynamic Agents activation. Capture action and result separately.

## Gotchas

- Focus changes the selected pane and activates a real app. Do not run it against a user's live session without permission.
- Terminal activation identifies an app, not the exact window/tab within that app.
- A direct `perform()` call, successful CLI response, or frontend screenshot alone cannot establish a complete system Widget-click handoff.
