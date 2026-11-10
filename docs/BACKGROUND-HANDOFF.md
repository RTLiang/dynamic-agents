# Background App activation

The native package contains the main App and its Widget extension. The main App owns ActivityKit and monitoring. Widget rows use Button(intent:); FocusAgentIntent executes in the Widget extension with background mode.

The Widget validates its containing installed App and starts it through NSWorkspace with activates = false and hides = true when needed. Monitoring and the request receiver start independently of any dashboard window.

Requests carry a UUID and a validated Hook session ID. The bounded base64 JSON travels in a distributed notification's object string with empty userInfo. Retries, acknowledgments and bounded deduplication prevent repeated activation. The main action refreshes Hook state, validates a currently running host identity and activates that App. Window and conversation selection stays under the host's control. Errors return to the Widget without opening a dashboard alert.

Live Activity recovery preserves the enabled preference when an activity ends. A missing system registration must remain absent across multiple checks after a propagation grace period before the App recreates it. Hook polling does not wait on ActivityKit operations, so a slow activity service does not stop session monitoring. ActivityKit can reject a cold-background creation with ActivityAuthorizationError.visibility (“Target is not foreground”) even when activities are authorized. The App keeps monitoring enabled, explains that it must be opened in the foreground, and stops repeated background requests for that error. Foreground activation retries immediately; visibility propagation and other transient failures use backoff. The App never activates its dashboard automatically to bypass this restriction. Explicit dismissal or switching the activity off keeps it off. Settings offers Restart Live Activity for a user-requested recreation when the system still reports an activity but its presentation is missing. Lifecycle logs include state/count/error codes, not session names or content.

There is no auxiliary handoff App. Only the explicit dashboard link opens the dashboard. Neither regular monitoring nor session actions need Apple Events or Accessibility APIs. The installer retains narrow legacy-helper cleanup for upgrades.

A direct handoff verification and an actual system-row click are different evidence. For system clicks, verify Widget start, main completion, Widget ACK, exact foreground host PID, retained host window selection and no main-App activation. See [native verification](NATIVE-VERIFICATION.md).
