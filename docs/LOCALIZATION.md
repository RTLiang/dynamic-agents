# Localization

The app supports English and Simplified Chinese, following macOS language preferences or the per-app language setting. English is the fallback. Restart the app after changing its language.

Translations reside in `Sources/AgentCore/Resources/<language>.lproj/`. `Localizable.strings` holds labels, status names, errors, accessibility hints and formatted messages; `Localizable.stringsdict` supplies plural rules. Both the app and Widget include these resources; the Companion package embeds the SwiftPM resource bundle.

User-provided session titles, project names, paths and agent brands are not translated. Live Activity payloads carry semantic status values and the app's supported language identifier. The Widget uses that identifier for compact labels, expanded status text, stale/offline messages, overflow links, accessibility labels and action hints, even when its process has a different default locale. The action also carries the language for Widget-side errors. Older payloads without the language field fall back to the Widget's supported language.

To add a language, create its `.lproj` resources, register it in the project generator, both application plists and `scripts/check-localizations.py`, and run:

```bash
python3 scripts/check-localizations.py
swift test --build-system native
```

The checker verifies key parity, nonempty translations, format arguments, plural fallbacks and source references. Tests cover supported languages, regional fallback, plural counts and dynamic parameters.
