# Codex background sessions

Users see coding conversations in the dashboard while Codex's internal memory tasks stay out of the session list. A normal conversation about memory remains visible when it completes.

## Sub-features

- `codex-background-exclusion`: internal and older subagent memory threads do not appear as coding sessions.
- `codex-memory-user-completion`: a normal memory-project conversation appears as Completed.
- `codex-sparse-background`: a later event without metadata does not restore a known background thread.
- `codex-hook-removal`: removing the adapter hides its existing reports from the dashboard.

## How to get to it (user POV)

- Connection Settings → Agent Integrations → Manage Integrations → Desktop Clients → Install for Codex.
- Start and complete a coding conversation in Codex, then return to the Dynamic Agents dashboard.
- Remove the Codex hook from Desktop Clients to stop showing its reports.

## Driving it with AX

Preconditions: a fresh isolated `control launch` run; `"$C" doctor "$RUN"` passes with the two baseline herdr rows. Codex is initially uninstalled in the run's private configuration. The harness supplies controlled external Codex events at the production hook input boundary.

- **Install and deliver events:** run `"$C" desktop-memory "$RUN" | tee "$E/desktop-memory.txt"`. It opens the settings and Desktop Clients tab, presses Install for Codex and records `desktop-memory-installed.json`.
- **Retain the user conversation:** the journey delivers prompt, stop and sparse-stop events for `Memory project example` through the UI-installed helper. `desktop-memory-records.json` must contain its user classification and done state. The dashboard must show that title with Completed and exactly three agents: the two baseline rows and this completion.
- **Exclude background work:** the same journey delivers internal and older subagent memory events, including sparse stops. Their records must remain ended. Neither `Background memory example` nor `Background legacy memory example` may appear in `desktop-memory-dashboard.json`. File state alone is insufficient: require the AX dashboard assertion and count.
- **Remove through the UI:** the journey reopens Desktop Clients, presses Remove for Codex, returns to the dashboard and requires two agents with the ordinary Codex completion gone. Capture is automatic in `desktop-memory-removed.json`.
- **Proof:** require `PASS: desktop-memory`, both event JSON files, the installed/dashboard/removed AX snapshots and `hook-consistency-after.json` with `passed: true`. Run the normal cleanup, then confirm these artifacts still exist under `$E` while scratch and the owned socket are absent.

## Gotchas

- The fixture schedules explicit lifecycle input; it does not launch real Codex or prove that a vendor trusted the hook or scheduled memory work. Record that limitation when reporting the result.
- The user completion can be verified after its runtime exits. This journey does not establish Running or host attribution from an open app.
- Missing or unreadable source metadata retains the bridge's existing behavior. Do not claim that every possible future memory format is covered.
- The Companion has no Widget. Dashboard exclusion does not prove system island counts, appearance or click routing.
- Running after another desktop journey can leave hooks installed or sheets open. Use a fresh run rather than weakening the initial Install precondition.
