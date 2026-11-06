# Connection and activity settings

Users configure herdr, terminal selection, menu icon visibility and how long recently completed sessions remain in the island.

## Sub-features

- `settings-duration-save`: save 7 minutes and reopen to confirm it persists.
- `settings-duration-cancel`: enter 3 minutes, cancel and confirm 7 remains.
- `settings-duration-bounds`: 1–1440 minutes, default 10; app clamps on Save.
- `settings-connection`: edit executable/session or select an application; cancel preserves existing values.
- `settings-icon`: hide or show the menu item; see [menu-bar.md](menu-bar.md).

## How to get to it (user POV)

- Choose the gear-shaped `Connection Settings` toolbar button.
- Press Command-comma while the dashboard is active.
- Configure `Show Completed For` in the `Live Activity` section, then choose `Save` or `Cancel`.

## Driving it with AX

Preconditions: isolated fixture instance is ready via `"$C" doctor "$RUN"`; dashboard toolbar is visible.

- **Save, reopen, cancel:** `"$C" duration "$RUN" | tee "$E/settings-duration.txt"`. Require all `result:` lines and `PASS: settings-duration`; the helper drives the real settings sheet and checks the isolated preferences domain. No terminal focus or real herdr command is issued.
- **Inspect:** `"$C" press "$RUN" AXButton 'Connection Settings'`; `"$C" snapshot "$RUN" > "$E/settings-open.json"`; require `completion-window-minutes`, the `Show Completed For` label and Save/Cancel. Close with `"$C" press "$RUN" AXButton Cancel`.
- **Other entry points and bounds:** use the AX tree and user input to exercise Command-comma, 1, 1440 and out-of-range entries separately. Reopen settings and check the rendered saved value. Record each entry and result. These are not covered by the `duration` shortcut.

## Gotchas

- The Companion never displays a system island. A saved duration alone does not prove activity expiration or automatic hiding; test those on a dedicated native session.
- Entering a new executable or terminal can affect discovery; use the disposable bundle and Cancel unless a dedicated fixture exists.
- Closing the sheet without `Save` must not persist the duration or menu icon setting.
