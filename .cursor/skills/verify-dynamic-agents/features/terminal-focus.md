# Terminal focus

Dashboard, menu and system Widget actions select an existing agent page in the chosen herdr client. Ghostty, iTerm2 and Apple Terminal use native surface identity plus the selected client's Go to navigator. Repeat clicks preserve the set of terminal surfaces.

## Preconditions

Use an unlocked GUI, a supported terminal, Automation and Accessibility authorization, and owned disposable herdr sessions. Honor authorization already present in the conversation. The Companion fixture cannot prove real terminal navigation. Check lock state before sending any event; a failed precondition stops the UI journey while independent builds and model checks may continue.

## Journeys

1. Capture each client's PID, creation time, TTY, session, native window/surface and current pane. Prefer a unique ordinary herdr client in Automatic mode; manually selected clients remain authoritative.
2. In each of Ghostty, iTerm2 and Apple Terminal, create two owned clients of one disposable session. Select a different pane in the chosen client through the dashboard. Verify its navigator reports the target pane and the other client retains its page.
3. Repeat the action. Require identical before/after terminal surface sets and the same selected page; no new window, tab or attachment process should appear.
4. Repeat through the menu and a real system activity row. For system actions record the Widget Intent acknowledgement, target app/surface, zero main-app activations and no auxiliary App or Dock item. Label AXPress and actual pointer clicks separately. For pointer tests verify the topmost hit element belongs to the visible activity; cached closed-popover coordinates are insufficient.
5. Select another client, a different session and a closed client in turn. Require the manual anchor and session scope to hold. A stale activity cannot select a same-named pane in another session. An attachment to a different agent must return an error instead of receiving navigation keys.
6. Exercise the App running and not running. The Widget Intent must wake the installed main app in the background and receive acknowledgement without activating either an auxiliary App or the dashboard.

Capture before/action/after independently. Keep PID/TTY, navigation text, app activation traces and native surface sets under ignored `.build/`. A global server `focused_pane_id` is isolation evidence only; it does not prove a client's selected page.

## Existing probes

`HERDR_LIVE_TEST=1 swift test --build-system native` checks read-only discovery. `scripts/verify-terminal.sh` runs the shared native action and reports `exactWindowVerified` and `terminalViewsUnchanged`. Native `--verify-live-activity` directly invokes the common action and checks background activation; it is not a system control click.

Use observed results for vendor coverage. Script compilation checks grammar and dictionary contracts only. General desktop editor hooks activate the observed host app; exact editor conversation selection remains outside this flow.
