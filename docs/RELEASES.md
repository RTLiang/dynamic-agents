# Local releases and code checks

CI runs the `Checks` workflow for Swift tests, desktop-hook tests, localization, generated-project consistency, shell syntax, and Companion compilation. CI does not build or publish release archives. Version tags do not trigger a release workflow.

## Build the native release on a Mac

Use an Apple silicon Mac with a macOS 27.3 SDK, `trash`, and GitHub CLI. The native release contains the main App and Widget. The SwiftPM Companion does not contain a Widget and must not be uploaded as the native release.

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --build-system native -j 4
python3 scripts/test-desktop-hooks.py
python3 scripts/check-localizations.py
python3 scripts/generate-project.py

APP_VERSION=0.1.1 APP_BUILD=33 APP_SIGNING_IDENTITY=- \
  bash scripts/package-release.sh
```

`package-release.sh` builds locally and verifies matching app/Widget versions, arm64 architecture, minimum macOS version, both languages, a valid bundle structure, and the absence of auxiliary Apps. Builds strip debug maps before signing, and packaging rejects embedded local user paths. It produces these ignored artifacts:

- `dist/releases/DynamicAgents-0.1.1-arm64.zip`
- `dist/releases/DynamicAgents-0.1.1-arm64.zip.sha256`
- `dist/releases/DynamicAgents-0.1.1-arm64.zip.manifest.json`

The manifest identifies the source commit and whether the checkout was dirty. Publishing requires a clean build from a commit already on `origin/main`. Finish and push source changes, then package the final revision. Do not rebuild an installed, authorized App just to repeat a test: an ad-hoc identity change can require renewing its Accessibility grant.

## Signing and first launch

Public packages use no Apple Developer ID certificate and are not notarized. Native Apple silicon executables and the sandboxed Widget retain the local ad-hoc signature needed to run. Removing that signature is not equivalent to disabling Gatekeeper: a user-side Open Anyway approval cannot repair a binary that the platform cannot execute.

Users approve first launch in **System Settings → Privacy & Security → Open Anyway** when macOS offers it. Terminal navigation also needs **Accessibility** and the terminal's **Automation** permission. After replacing an ad-hoc App, an enabled old Accessibility entry can refer to the previous identity; the user can remove that one entry and add the new App from Applications. The user completes authentication. The app and tooling do not change the TCC database or handle passwords.

## Publish the verified local archive

Create English/Chinese notes in `docs/releases/<version>.md`. Run the project verification skill against the features that changed and retain evidence under ignored `.build/`. Publishing only uploads the existing local archive; it does not invoke CI or rebuild it.

```bash
bash scripts/publish-release.sh 0.1.1 docs/releases/0.1.1.md
```

The publisher verifies the checksum and manifest, checks that the source revision is clean and on `origin/main`, refuses an existing release, and uses `gh release create --target <commit>` to create the version tag and upload the files. It refuses to run in GitHub Actions. Published assets are not silently overwritten.

After publishing, verify the public release tag, asset names, source commit and downloaded ZIP checksum. The GitHub release must expose `DynamicAgents-<version>-arm64.zip`; the app's update checker recognizes that name.

## In-app update checks

The app checks the public latest-release API, accepts stable semantic versions from this repository, and opens the release page rather than installing anything. Automatic checks run at most daily and can be disabled. Manual checks show the result. No session content is uploaded.

The verification Companion disables automatic checks with process-local launch arguments. CI tests do not establish native Widget presentation, system clicks, vendor hook trust, or terminal navigation; those have separate local journeys.
