#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:-}"
notes="${2:-}"
if [[ ! "$version" =~ ^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$ || ! -f "$notes" ]]; then
  echo 'Usage: scripts/publish-release.sh <stable-version> <release-notes-file>' >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin || "${GITHUB_ACTIONS:-false}" == true ]]; then
  echo 'Release publishing must run on a local Mac, not in CI.' >&2
  exit 1
fi
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit source changes before publishing.' >&2; exit 1; }
commit="$(git rev-parse HEAD)"
python3 - "$version" "$commit" <<'PY'
import subprocess
import sys
ref = 'refs/tags/v' + sys.argv[1]
output = subprocess.check_output(['git', 'ls-remote', '--tags', 'origin', ref, ref + '^{}'], text=True, timeout=20)
refs = dict(line.split()[::-1] for line in output.splitlines())
existing = refs.get(ref + '^{}', refs.get(ref))
assert existing is None or existing == sys.argv[2], 'Version tag already points to another commit'
PY
[[ "$commit" == "$(git rev-parse origin/main)" ]] || { echo 'Push the release source to origin/main first.' >&2; exit 1; }
archive="DynamicAgents-$version-arm64.zip"
for file in "$archive" "$archive.sha256" "$archive.manifest.json"; do
  [[ -f "dist/releases/$file" ]] || { echo "Missing local artifact: $file" >&2; exit 1; }
done
(cd dist/releases && shasum -a 256 -c "$archive.sha256")
python3 - "dist/releases/$archive.manifest.json" "$version" "$commit" <<'PY'
import json
import sys
from pathlib import Path
value = json.loads(Path(sys.argv[1]).read_text())
assert value['version'] == sys.argv[2] and value['sourceCommit'] == sys.argv[3], 'Artifact source/version mismatch'
assert value['sourceDirty'] is False and value['builtLocally'] is True, 'Repackage the clean source on this Mac'
assert value['signing'] == 'ad-hoc' and value['notarized'] is False, 'Unexpected release signing policy'
PY
repo='RTLiang/dynamic-agents'
tag="v$version"
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  echo 'This release already exists; refusing to replace published assets.' >&2
  exit 1
fi
gh release create "$tag" "dist/releases/$archive" "dist/releases/$archive.sha256" "dist/releases/$archive.manifest.json" \
  --repo "$repo" --target "$commit" --title "Dynamic Agents $version" --notes-file "$notes" --latest
