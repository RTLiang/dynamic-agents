# Terminal focus

Dashboard, menu and system Widget actions select an existing agent page in the chosen herdr client. Ghostty, iTerm2 and Apple Terminal use native surface identity and a uniquely matched existing sidebar row. Normal actions never open Go to; the diagnostic page reader may use it outside the measured action. Repeat clicks preserve the set of terminal surfaces.

## Sub-features

- `terminal-existing-page`: open the target page in the selected client and preserve another client's page.
- `terminal-repeat`: repeat navigation without creating a window, tab or attachment.
- `terminal-selection`: honor explicit client/session choices and reject stale or closed targets.
- `terminal-background`: warm and cold Widget actions focus the terminal with no dashboard or auxiliary-App activation.

## How to get to it (user POV)

- Select an agent in the dashboard, then double-click, press Return, use its context menu or choose the toolbar action.
- Choose the agent from the menu bar or select its expanded system Live Activity row.
- Use Connection Settings → Open With / herdr Window to choose the client.

## Driving it with AX

Preconditions: an unlocked GUI, a supported terminal, Automation and Accessibility authorization, and owned disposable herdr sessions. Honor authorization already present in the conversation. The Companion fixture cannot prove real terminal navigation. Check lock state before sending any event; a failed precondition stops the UI journey while independent builds and model checks may continue.

1. Capture each client's PID, creation time, TTY, session, native window/surface and current pane. Prefer a unique ordinary herdr client in Automatic mode; manually selected clients remain authoritative.
2. In each of Ghostty, iTerm2 and Apple Terminal, create two owned clients of one disposable session. Select a different pane in the chosen client through the dashboard. Observe that the action stays on the normal herdr surface with no chooser, and independently inspect the target pane after the action. A diagnostic Go to read must be outside action timing. Require the other client to retain its page.
3. Repeat the action. Require identical before/after terminal surface sets and the same selected page; no new window, tab or attachment process should appear.
4. Repeat through the menu and a real system activity row. For system actions record the Widget Intent acknowledgement, target app/surface, zero main-app activations and no auxiliary App or Dock item. Label AXPress and actual pointer clicks separately. For pointer tests verify the topmost hit element belongs to the visible activity; cached closed-popover coordinates are insufficient.
5. Select another client, a different session and a closed client in turn. Require the manual anchor and session scope to hold. A stale activity cannot select a same-named pane in another session. An attachment to a different agent must return an error instead of receiving navigation keys.
6. Exercise the App running and not running. The Widget Intent must wake the installed main app in the background and receive acknowledgement without activating either an auxiliary App or the dashboard.

Capture before/action/after independently. Keep PID/TTY, navigation text, app activation traces and native surface sets under ignored `.build/`. A global server `focused_pane_id` is isolation evidence only; it does not prove a client's selected page.

## Gotchas

`HERDR_LIVE_TEST=1 swift test --build-system native` checks read-only discovery. `scripts/verify-terminal.sh` runs the shared native action and reports `exactWindowVerified` and `terminalViewsUnchanged`. Native `--verify-live-activity` directly invokes the common action and checks background activation; it is not a system control click.

Use observed results for vendor coverage. Script compilation checks grammar and dictionary contracts only. General desktop editor hooks activate the observed host app; exact editor conversation selection remains outside this flow.
