#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description="Check captured chronod logs for this app's Widget rendering result.")
parser.add_argument("log", type=Path)
parser.add_argument("--activity-id")
args = parser.parse_args()
lines = [line for line in args.log.read_text().splitlines() if "dev.local.dynamicagents" in line]
if args.activity_id:
    lines = [line for line in lines if args.activity_id in line]
failures = [line for line in lines if "Reload failed" in line or "Unable to create new WidgetExtensionSession" in line]
successes = [line for line in lines if "Reload success" in line]
result = {"passed": bool(successes) and not failures, "successfulRenders": len(successes), "failedRenders": len(failures)}
print(json.dumps(result, indent=2))
raise SystemExit(0 if result["passed"] else 1)
