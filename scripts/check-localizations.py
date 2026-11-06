#!/usr/bin/env python3
"""Check translation coverage and matching format arguments."""
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources/AgentCore/Resources"
LANGUAGES = ("en", "zh-Hans")


def load_strings(path):
    result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], check=True, capture_output=True)
    return json.loads(result.stdout)


def placeholders(value):
    return sorted(re.findall(r"%(?:\d+\$)?(?:lld|@)", value.replace("%%", "")))


strings = {language: load_strings(RESOURCES / f"{language}.lproj/Localizable.strings") for language in LANGUAGES}
plurals = {language: plistlib.loads((RESOURCES / f"{language}.lproj/Localizable.stringsdict").read_bytes()) for language in LANGUAGES}
for language in LANGUAGES:
    assert strings[language].keys() == strings["en"].keys(), f"String keys differ: {language}"
    assert plurals[language].keys() == plurals["en"].keys(), f"Plural keys differ: {language}"
    for key, value in strings[language].items():
        assert value.strip(), f"Empty translation: {language}/{key}"
        assert placeholders(value) == placeholders(strings["en"][key]), f"Format arguments differ: {language}/{key}"
    for key, value in plurals[language].items():
        assert value["count"]["NSStringFormatSpecTypeKey"] == "NSStringPluralRuleType"
        assert value["count"]["NSStringFormatValueTypeKey"] == "lld"
        assert value["count"]["other"].strip(), f"Missing plural fallback: {language}/{key}"
        for category, translation in value["count"].items():
            if not category.startswith("NSString"):
                assert placeholders(translation) == placeholders(plurals["en"][key]["count"]["other"]), f"Plural arguments differ: {language}/{key}"

keys = set(strings["en"]) | set(plurals["en"])
used = set()
for directory in (ROOT / "Sources", ROOT / "WidgetExtension"):
    for source in directory.rglob("*.swift"):
        content = source.read_text()
        used.update(re.findall(r'L10n\.(?:text|format)\("([^"\n]+)"', content))
        used.update(re.findall(r'(?:LocalizedStringResource = |@Parameter\(title: )"([^"\n]+)"', content))
        if "Verification" not in source.name:
            assert not re.search(r"[\u4e00-\u9fff]", content), f"Hardcoded UI text: {source.relative_to(ROOT)}"
assert not used - keys, f"Missing translation keys: {sorted(used - keys)}"
print(f"Validated {len(keys)} keys in {', '.join(LANGUAGES)}; all source references and format arguments match.")
