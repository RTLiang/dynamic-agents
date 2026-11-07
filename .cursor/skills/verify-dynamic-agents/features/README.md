# Dynamic Agents verification map

Use the isolated Companion fixture and `$C`, `$RUN`, `$E` from [the launch recipe](../SKILL.md). Start each journey from a fresh launch unless it says otherwise. The two fixture rows are `Build example` (Codex, Running) and `Review example` (Claude Code, Idle), both in project `Example`.

Capture commands, resulting AX trees and side effects; report each tested entry point separately. Unmet preconditions are failures or skips, not passes. The fixture disallows real pane focusing; Companion has no Widget. Real native or terminal tests require their additional prerequisites and scoped authorization; see those feature files.

## Features

- [Dashboard and search](dashboard.md): list, search, empty state, filtering and selection.
- [Connection and activity settings](settings.md): completion retention, Save and Cancel, connection fields.
- [Menu bar visibility](menu-bar.md): hide and restore without quitting.
- [Desktop client hooks](desktop-hooks.md): local lifecycle adapters, helper consistency, hook trust and host identity outside herdr.
- [Codex background sessions](codex-background-sessions.md): keep ordinary user completions visible while excluding internal memory tasks, then remove the adapter through the UI.
- [Agent integrations](integrations.md): inspect, install, update and remove herdr-managed hooks/plugins.
- [Terminal focus](terminal-focus.md): focus and activate the correct terminal.
- [Live Activity](live-activity.md): system presentation, filtering, lifecycle and interaction.
