# Background App activation

The native package contains the main App and its Widget extension. The main App owns ActivityKit and monitoring. Widget rows use Button(intent:); FocusAgentIntent executes in the Widget extension with background mode.

The Widget validates its containing installed App and starts it through NSWorkspace with activates = false and hides = true when needed. Monitoring and the request receiver start independently of any dashboard window.

Requests carry a UUID and a validated Hook session ID. The bounded base64 JSON travels in a distributed notification's object string with empty userInfo. Retries, acknowledgments and bounded deduplication prevent repeated activation. The main action refreshes Hook state, validates a currently running host identity and activates that App. Window and conversation selection stays under the host's control. Errors return to the Widget without opening a dashboard alert.

There is no auxiliary handoff App. Only the explicit dashboard link opens the dashboard. Neither regular monitoring nor session actions need Apple Events or Accessibility APIs. The installer retains narrow legacy-helper cleanup for upgrades.

A direct handoff verification and an actual system-row click are different evidence. For system clicks, verify Widget start, main completion, Widget ACK, exact foreground host PID, retained host window selection and no main-App activation. See [native verification](NATIVE-VERIFICATION.md).
