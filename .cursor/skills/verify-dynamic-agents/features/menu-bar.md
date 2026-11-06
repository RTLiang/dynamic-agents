# Menu bar visibility

Users can hide the status item without quitting the app or stopping its activity, and later restore it.

## Sub-features

- `menu-hide-settings`: hide the item via settings and Save.
- `menu-restore-settings`: reopen settings and show it again.
- `menu-hide-menu`: choose `Hide Menu Bar Icon` from the item itself.
- `menu-survival`: close the window, reopen from Dock, and confirm the app remains running.

## How to get to it (user POV)

- Open the menu bar item and select `Hide Menu Bar Icon`.
- In `Connection Settings` → `Appearance`, change `Show Menu Bar Icon` and Save.
- After hiding, reopen the app from Dock; use settings or the View menu to restore the item.

## Driving it with AX

Preconditions: fresh isolated fixture, dashboard toolbar visible; `"$C" doctor "$RUN"` passes.

- `"$C" menu "$RUN" | tee "$E/menu-before.txt"` must say `menu icon: present`.
- `"$C" press "$RUN" AXButton 'Connection Settings'`; `"$C" press "$RUN" AXCheckBox 'Show Menu Bar Icon'`; `"$C" press "$RUN" AXButton Save`.
- `"$C" menu "$RUN" | tee "$E/menu-hidden.txt"` must say `menu icon: absent`. `"$C" doctor "$RUN"` must still pass.
- Repeat the three settings presses and capture `$E/menu-restored.txt`; it must say `menu icon: present`.
- Separately exercise the menu command, close/reopen from Dock, and the View-menu restoration. Confirm the original PID stays alive and record each entry point; these paths are not covered by the settings toggle.

## Gotchas

- `menu` checks only the test process's own AXExtrasMenuBar; another instance's item must not count as the fixture's.
- The isolated Companion lacks a Widget. Continued native activity after hiding requires the exclusive native journey in [live-activity.md](live-activity.md).
- `Cancel` does not save settings changes; use Save for this journey.
