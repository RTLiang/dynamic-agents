#!/usr/bin/env python3
"""Exercise the production LiveActivityController with a deterministic transport double.

Only imports and platform availability are redirected in the test copies. No real
ActivityKit activities, production preferences, or installed App are accessed.
"""
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import uuid

root = Path(__file__).resolve().parent.parent
(root / ".build").mkdir(exist_ok=True)
owned = Path(tempfile.mkdtemp(prefix="activity-lifecycle-", dir=root / ".build"))
try:
    tests = root / "Tests/LiveActivityLifecycle"
    app = owned / "Lifecycle.app"
    binary = app / "Contents/MacOS/Lifecycle"
    binary.parent.mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "dev.local.dynamicagents.lifecycle" + uuid.uuid4().hex,
        "CFBundleExecutable": "Lifecycle", "CFBundlePackageType": "APPL",
    }))
    controller = (root / "Sources/DynamicAgents/LiveActivityController.swift").read_text()
    availability = "#if NATIVE_LIVE_ACTIVITIES\n        if #available(macOS 27.3, *) { return true }\n        #endif\n        return false"
    assert controller.count(availability) == 1, "Review the test's platform guard substitution"
    controller = controller.replace("import ActivityKit", "import ActivityKitTestDouble").replace(availability, "return true")
    (owned / "Controller.swift").write_text(controller)
    attributes = (root / "Sources/DynamicAgents/Shared/AgentActivityAttributes.swift").read_text()
    attributes = attributes.replace("import ActivityKit", "import ActivityKitTestDouble").replace("@available(macOS 27.3, *)", "")
    (owned / "Attributes.swift").write_text(attributes)
    flags = ["xcrun", "swiftc", "-swift-version", "5"]
    subprocess.run(flags + ["-emit-module", "-emit-library", "-module-name", "ActivityKitTestDouble",
                           str(tests / "ActivityKitTestDouble.swift"), "-emit-module-path", str(owned / "ActivityKitTestDouble.swiftmodule"),
                           "-o", str(owned / "libActivityKitTestDouble.dylib")], check=True, timeout=60)
    subprocess.run(flags + ["-parse-as-library", "-module-name", "DynamicAgents", "-D", "NATIVE_LIVE_ACTIVITIES",
                           "-I", str(owned), "-L", str(owned), "-lActivityKitTestDouble", "-Xlinker", "-rpath", "-Xlinker", str(owned),
                           *map(str, sorted((root / "Sources/AgentCore").glob("*.swift"))), str(owned / "Controller.swift"),
                           str(owned / "Attributes.swift"), str(tests / "Harness.swift"), "-o", str(binary)], check=True, timeout=60)
    subprocess.run([str(binary), str(owned / "result.json")], check=True, timeout=20)
    result = json.loads((owned / "result.json").read_text())
    assert result and all(row["passed"] for row in result)
    print(f"PASS: {len(result)} production-controller lifecycle scenarios (transport double; not system presentation)")
finally:
    subprocess.run(["trash", str(owned)], check=True)
