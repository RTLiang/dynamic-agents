# Local releases and code checks

CI runs Swift tests, Python installer/report tests, the Pi extension lifecycle journey, scope and localization checks, generated-project consistency, shell syntax and Companion compilation. CI does not publish releases.

## Build on a local Mac

Use Apple silicon, a macOS 27.3+ SDK, Python 3, Node 24+, trash, hdiutil and GitHub CLI. The native package contains the main App and its Widget; the SwiftPM Companion has no Widget.

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --build-system native -j 4
python3 scripts/test-desktop-hooks.py
node scripts/test-pi-hook.mjs
python3 scripts/test-live-activity-lifecycle.py
python3 scripts/check-localizations.py
python3 scripts/check-app-scope.py
python3 scripts/generate-project.py

APP_VERSION=0.2.0 APP_BUILD=35 APP_SIGNING_IDENTITY=- \
  bash scripts/package-release.sh
```

Packaging verifies matching app/Widget versions, arm64 architecture, deployment target, both languages, bundled Pi extension and no auxiliary App or Automation permission. Debug maps are stripped before signing; embedded local user paths are rejected. It creates a compressed DMG containing DynamicAgents.app and an Applications shortcut, verifies the disk image and produces:

- dist/releases/DynamicAgents-0.2.0-arm64.dmg
- dist/releases/DynamicAgents-0.2.0-arm64.dmg.sha256
- dist/releases/DynamicAgents-0.2.0-arm64.dmg.manifest.json

The manifest records source commit, dirty state, SDK, build and DMG format. Publish only from clean source already pushed to origin/main. Mount the final image read-only without opening Finder, verify the contained app/Widget versions, resources, signatures and Applications shortcut, then detach only that owned mount.

## Signing and installation

Public packages use the required local ad-hoc execution signature without Developer ID signing or notarization. Users open the DMG, drag the App to Applications, eject and launch the installed copy. If macOS blocks first launch, use Privacy & Security → Open Anyway. Host-App activation needs no Accessibility or Automation grant. Password and Touch ID prompts remain with the user.

## Publish

Write bilingual release notes, run the relevant [UI verification journeys](../.cursor/skills/verify-dynamic-agents/SKILL.md), commit/push and package the final clean revision locally.

```bash
bash scripts/publish-release.sh 0.2.0 docs/releases/0.2.0.md
```

The publisher validates checksum, source, clean manifest, DMG format and signing policy. It refuses existing releases and conflicting tags, then uploads the existing local DMG, checksum and manifest using GitHub CLI. It does not rebuild or invoke CI. Verify the public release tag, source, asset names and downloaded DMG checksum afterward.

## Update checks

The app accepts stable versions from this repository with the exact DynamicAgents-<version>-arm64.dmg asset. It opens the release page without installing. Automatic checks run at most daily and can be disabled; no session data is uploaded. Versions 0.1.x accepted only ZIP assets, so users upgrading from those versions must visit the Releases page manually.

Controlled UI, direct actions, native lifecycle, vendor trust and actual system Widget clicks provide different evidence. Record only the journeys actually performed for the new binary.
