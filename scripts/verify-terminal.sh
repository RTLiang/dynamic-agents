#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="${1:-$PWD/dist/DynamicAgents-Companion.app}"
mkdir -p .build
report_path="$(mktemp "$PWD/.build/terminal-verification.XXXXXX")"
"$app_path/Contents/MacOS/DynamicAgents" --verify-terminal "$report_path" > "$report_path.log" 2>&1 &
probe_pid=$!
trap 'kill -TERM "$probe_pid" 2>/dev/null || true' EXIT
for attempt in $(seq 1 100); do
  if [[ -s "$report_path" ]]; then
    python3 - "$report_path" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
report = json.loads(path.read_text())
print(json.dumps(report, indent=2, ensure_ascii=False))
print(f"Report: {path}")
sys.exit(0 if report.get("passed") else 1)
PY
    exit 0
  fi
  if ! kill -0 "$probe_pid" 2>/dev/null; then
    echo "Verification app exited. See $report_path.log" >&2
    exit 1
  fi
  sleep 0.2
done
echo "Verification timed out. See $report_path.log" >&2
exit 1
