# Dashboard and search

The main window lists agents and lets users narrow the list by text and status before opening a terminal.

## Sub-features

- `dashboard-list`: see agent, project, type and status.
- `search-match`, `search-empty`, `search-clear`: find matching rows, show a no-result state and restore rows.
- `filter-status`: choose a status and restore All Statuses.
- `sort-select`: sort columns and select a row.

## How to get to it (user POV)

- Launch the app or open `Dynamic Agents` from the menu bar or Dock.
- Choose toolbar search and enter text; choose the status picker for status filters.
- Select a row; double-click, press Return, use its context menu or use the toolbar to open it.

## Driving it with AX

Preconditions: fresh isolated fixture; `"$C" doctor "$RUN"` reports both rows. The fixture cannot focus a real terminal; use [terminal-focus.md](terminal-focus.md) for that journey.

- **Initial list:** `"$C" snapshot "$RUN" > "$E/list.json"`. The `agents-table` tree contains `Build example`, `Review example`, `Example`, `Codex`, `Claude Code`, `Running`, `Idle` and `herdr connected`.
- **Match:** `"$C" press "$RUN" AXButton Search`; `"$C" type "$RUN" AXTextField Build`; `"$C" snapshot "$RUN" > "$E/search-match.json"`. The tree contains `Build example` and excludes `Review example`.
- **Empty:** `"$C" type "$RUN" AXTextField nonexistent`; capture `$E/search-empty.json` with `snapshot`. Both fixture rows are absent and `No Matching Agents` is present.
- **Clear:** `"$C" type "$RUN" AXTextField ''`; capture `$E/search-clear.json`. Both fixture rows return.
- **Status and sorting:** inspect the AX tree for the `Status` picker and column headers; exercise each status and sort direction, retaining before/action/after evidence. The canned fixture includes Running and Idle only; other statuses require a controlled fixture change and must be reported separately.

## Gotchas

- Search can collapse other toolbar items. Start a fresh run for settings or menu journeys rather than assuming the gear remains accessible.
- `set role:AXTextField` changes AXValue without reliably triggering SwiftUI search. Use `type` and inspect the rows.
- Search results and screenshots from a real herdr session can contain private titles or paths; keep them local.
