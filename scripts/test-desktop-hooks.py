#!/usr/bin/env python3
"""Exercise desktop hook configuration and reports in private disposable directories."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "Sources/AgentCore/Resources/desktop-hook.py"


class DesktopHooks(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="dynamic-agents-hook-test-"))
        self.environment = dict(os.environ, DYNAMIC_AGENTS_DATA_DIR=str(self.directory / "data"),
                                DYNAMIC_AGENTS_CONFIG_HOME=str(self.directory / "config"))
        self.environment.pop("HERDR_ENV", None)

    def tearDown(self):
        subprocess.run(["trash", str(self.directory)], check=True)

    def run_hook(self, *args, payload=None, environment=None):
        return subprocess.run([sys.executable, str(SCRIPT), *args], input=json.dumps(payload or {}),
                              capture_output=True, text=True, env=environment or self.environment, timeout=4, check=True)

    def test_install_and_remove_preserve_existing_user_and_herdr_hooks(self):
        for source, name in [("claude", ".claude/settings.json"), ("codex", ".codex/hooks.json"), ("cursor", ".cursor/hooks.json"), ("copilot", ".copilot/hooks/dynamic-agents.json")]:
            with self.subTest(source=source):
                path = self.directory / "config" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                event = "sessionStart" if source in ("cursor", "copilot") else "SessionStart"
                existing = {"type": "command", "command": "echo existing-herdr-hook dynamic-agents-hook-v1"}
                entry = {"hooks": [existing]} if source in ("claude", "codex") else existing
                path.write_text(json.dumps({"other_setting": True, "hooks": {event: [entry]}}))
                self.run_hook("install", source)
                self.run_hook("install", source)
                self.assertTrue(json.loads(self.run_hook("status", source).stdout)["installed"])
                self.run_hook("remove", source)
                result = json.loads(path.read_text())
                self.assertTrue(result["other_setting"])
                self.assertEqual(result["hooks"][event], [entry])
                self.assertFalse(json.loads(self.run_hook("status", source).stdout)["installed"])

    def test_reports_contain_metadata_only_and_success_is_not_inferred_from_open_session(self):
        payload = {"session_id": "example-session", "cwd": "/example/project", "prompt": "PRIVATE PROMPT", "tool_input": {"secret": "PRIVATE TOOL INPUT"}}
        for event, expected in [("SessionStart", "idle"), ("UserPromptSubmit", "working"), ("PermissionRequest", "blocked"), ("PostToolUse", "working"), ("Stop", "done"), ("Interrupt", "idle"), ("SessionEnd", "ended")]:
            self.assertEqual(json.loads(self.run_hook("report", "codex", event, payload=payload).stdout), {})
            files = list((self.directory / "data/events").glob("*.json"))
            self.assertEqual(len(files), 1)
            text = files[0].read_text()
            self.assertEqual(json.loads(text)["status"], expected)
            self.assertNotIn("PRIVATE", text)
            self.assertNotIn("/example/project", text)
            self.assertEqual(json.loads(text)["project"], "project")

    def test_herdr_and_subagents_are_excluded_and_cursor_aborts_are_not_completed(self):
        env = dict(self.environment, HERDR_ENV="1")
        self.run_hook("report", "claude", "UserPromptSubmit", payload={"session_id": "a"}, environment=env)
        self.assertFalse((self.directory / "data/events").exists())
        self.run_hook("report", "claude", "Stop", payload={"session_id": "a", "agent_id": "child"})
        self.assertFalse((self.directory / "data/events").exists())
        payload = {"conversation_id": "cursor-example", "status": "aborted"}
        self.run_hook("report", "cursor", "stop", payload=payload)
        event = json.loads(next((self.directory / "data/events").glob("*.json")).read_text())
        self.assertEqual(event["status"], "unknown")
        result = self.run_hook("report", "cursor", "beforeSubmitPrompt", payload=payload)
        self.assertEqual(json.loads(result.stdout), {"continue": True})

    def test_removal_disables_existing_reports(self):
        self.run_hook("install", "codex")
        self.run_hook("report", "codex", "UserPromptSubmit", payload={"session_id": "example"})
        path = next((self.directory / "data/events").glob("*.json"))
        old = path.read_text()
        self.run_hook("remove", "codex")
        self.run_hook("report", "codex", "Stop", payload={"session_id": "example"})
        self.assertEqual(path.read_text(), old)
        self.assertFalse(json.loads((self.directory / "data/sources.json").read_text())["codex"])

    def test_cursor_reads_workspace_roots_without_cwd(self):
        payload = {"conversation_id": "cursor-roots", "workspace_roots": ["/example/frontend", "/example/backend"], "prompt": "PRIVATE PROMPT"}
        self.run_hook("report", "cursor", "beforeSubmitPrompt", payload=payload)
        text = next((self.directory / "data/events").glob("*.json")).read_text()
        self.assertEqual(json.loads(text)["project"], "frontend, backend")
        self.assertNotIn("/example/", text)
        self.assertNotIn("PRIVATE", text)

    def test_sparse_lifecycle_events_preserve_the_last_project(self):
        self.run_hook("report", "codex", "UserPromptSubmit", payload={"session_id": "sparse", "cwd": "/example/project"})
        self.run_hook("report", "codex", "Stop", payload={"session_id": "sparse"})
        path = next((self.directory / "data/events").glob("*.json"))
        result = json.loads(path.read_text())
        self.assertEqual(result["project"], "project")
        self.assertEqual(result["status"], "done")
        self.run_hook("report", "codex", "UserPromptSubmit", payload={"session_id": "sparse", "cwd": "/example/other"})
        self.assertEqual(json.loads(path.read_text())["project"], "other")

    def test_outdated_managed_helper_remains_installed_and_can_be_updated(self):
        self.run_hook("install", "codex")
        helper = self.directory / "data/desktop-hook.py"
        helper.write_text(helper.read_text() + "\n# Previous shipped version\n")
        status = json.loads(self.run_hook("status", "codex").stdout)
        self.assertTrue(status["installed"])
        self.assertFalse(status["current"])
        self.run_hook("install", "codex")
        updated = json.loads(self.run_hook("status", "codex").stdout)
        self.assertTrue(updated["installed"])
        self.assertTrue(updated["current"])

    def test_invalid_configuration_is_not_overwritten(self):
        path = self.directory / "config/.codex/hooks.json"
        path.parent.mkdir(parents=True)
        path.write_text("not valid json")
        result = subprocess.run([sys.executable, str(SCRIPT), "install", "codex"], capture_output=True, env=self.environment, timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_text(), "not valid json")


if __name__ == "__main__":
    unittest.main()
