# Native UI and Hook monitoring

The main window uses a native SwiftUI table with search, status filtering, sorting and app activation. Settings manage the menu icon, completion retention, lifecycle adapters and update checks.

The monitor reads local Hook reports every second. It resolves regular running Apps from current process identity and event time. Verified live detached CLI runtimes remain monitorable; known environment hints can supply an App target. Opening a session activates that running App, leaving window, tab and conversation selection to the host.

Completion time comes from the lifecycle event. Reminder retention is evaluated against that original time, including after app restart; reading it does not refresh the timer. Available expired sessions become Idle, unavailable sessions disappear. See [domain language](../GLOSSARY.md).

The main App owns ActivityKit and continues monitoring with no dashboard window or menu icon. Widget rows use background App Intents. The optional SwiftPM Companion exercises UI and model code without a Widget. See [native verification](NATIVE-VERIFICATION.md).
