# Terminal focus

Dashboard, menu and background Widget actions open the selected agent in its herdr session and terminal window. Reuse an existing dedicated attachment; otherwise create a tab in the selected Ghostty/iTerm2 window, or a separate Apple Terminal window. Public herdr focus broadcasts are intentionally absent.

## Entry points

Double-click a dashboard row, press Return on a selected row, use Open in Terminal, select a menu-bar agent, or click an expanded system Live Activity row. All entries use the same store action.

## Preconditions

Use an unlocked GUI, a supported terminal with Automation consent, and dedicated herdr sessions. Honor user authorization already present in the conversation before requesting it again. Real focus opens or activates terminal views; use isolated owned sessions for new probes. The fixture only supports snapshot/status and integration requests; it cannot prove native window handoff.

## Journeys

1. Run `HERDR_LIVE_TEST=1 swift test --build-system native` for read-only discovery. Record clients, PID/TTY and session distinctions in ignored evidence.
2. Open two terminal windows with different named herdr sessions. Configure one session; click its dashboard agent. Confirm the new attachment uses that session and the intended window, while the other window retains its workspace/tab/pane.
3. Open two clients of the same session. Choose one in Connection Settings → herdr Window; click its agent. Confirm only that window gets a new attachment and that the original views retain their selections. Repeat the click: the existing attachment is selected without another tab.
4. Select the other session in settings, then invoke the old scoped agent action. It must not open a same-named pane in the new session. Close the chosen client and retry: report its absence without choosing another window.
5. Repeat required entries through the menu and system Widget. For Widget actions, observe activation notifications and require zero Dynamic Agents activations.

For each action capture before/action/after separately: native terminal window and selected surface IDs, the attachment client TTY/PID/argv, unchanged original client locations and frontmost application. A global `focused_pane_id` remaining unchanged helps demonstrate isolation but cannot prove the right window is frontmost.

`bash scripts/verify-terminal.sh` opens/reuses the current agent attachment and reports `exactWindowVerified` using native surface identity. Native `--verify-live-activity` calls the real intent directly and checks the same condition; see [live-activity.md](live-activity.md). These probes do not establish a physical system Widget click.

## Boundaries

A locked screen or absent Automation permission blocks real window verification; report that precondition and retain build/model evidence. AppleScript compilation only checks grammar and dictionary contracts. Unsupported terminals fail explicitly. General desktop editor hooks activate the observed host app; selecting a particular editor conversation is outside this capability. Keep logs, window IDs, paths and session data under ignored `.build/`.
