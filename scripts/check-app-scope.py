#!/usr/bin/env python3
"""Guard the hook-only, app-activation-only product boundary."""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parent.parent
for directory in [root / "Sources", root / "WidgetExtension"]:
    for path in directory.rglob("*"):
        if not path.is_file() or path.suffix not in (".swift", ".py", ".ts"):
            continue
        content = path.read_text()
        for forbidden in ["herdr", "Herdr", "AXUIElement", "NSAppleScript", "CGEvent(", "TIOCGWINSZ", "terminalClientID"]:
            assert forbidden not in content, f"Removed navigation dependency in {path.relative_to(root)}: {forbidden}"
info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
entitlements = plistlib.loads((root / "Resources/App.entitlements").read_bytes())
assert "NSAppleEventsUsageDescription" not in info
assert "com.apple.security.automation.apple-events" not in entitlements
store = (root / "Sources/DynamicAgents/AgentStore.swift").read_text()
assert "openApplication" not in store and "launchApplication" not in store
print("PASS: hook-only monitoring, host-app activation, no terminal/window automation or automation permission")
