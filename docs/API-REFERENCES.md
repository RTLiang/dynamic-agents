# API references

- [ActivityKit](https://developer.apple.com/documentation/activitykit/activity) and [WidgetKit ActivityConfiguration](https://developer.apple.com/documentation/widgetkit/activityconfiguration): genuine system Live Activities on macOS 27.3+.
- [Widget extension App Intent target](https://developer.apple.com/documentation/appintents/intentexecutiontargets/widgetkitextension): session actions execute in the Widget, then relay a bounded request to the main App. See [handoff](BACKGROUND-HANDOFF.md).
- [NSRunningApplication.activate](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)): activates an existing host process.
- [Claude hooks](https://code.claude.com/docs/en/hooks), [Codex hooks](https://developers.openai.com/codex/hooks/), [Cursor hooks](https://cursor.com/docs/agent/hooks), and [Copilot hooks](https://code.visualstudio.com/docs/copilot/customization/hooks): external lifecycle boundaries.
- Pi's extension API supplies session metadata, runtime PID and lifecycle events. The adapter requires its final agent_settled boundary; low-level agent_end is insufficient during automatic retries. See [hook details](DESKTOP-HOOKS.md).
