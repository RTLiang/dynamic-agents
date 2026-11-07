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

    def test_completion_time_survives_duplicate_stop_viewing_and_close_but_new_work_clears_it(self):
        payload = {"session_id": "completion-example"}
        self.run_hook("report", "codex", "Stop", payload=payload)
        path = next((self.directory / "data/events").glob("*.json"))
        event = json.loads(path.read_text())
        completed = event["completedAt"] - 100
        event["completedAt"] = completed
        path.write_text(json.dumps(event))
        for name in ["Stop", "SessionStart", "SessionEnd"]:
            self.run_hook("report", "codex", name, payload=payload)
            self.assertEqual(json.loads(path.read_text())["completedAt"], completed)
        self.run_hook("report", "codex", "UserPromptSubmit", payload=payload)
        self.assertNotIn("completedAt", json.loads(path.read_text()))
        self.run_hook("report", "codex", "Interrupt", payload=payload)
        self.assertNotIn("completedAt", json.loads(path.read_text()))

    def test_host_app_hint_is_known_metadata_and_unknown_values_are_not_saved(self):
        payload = {"session_id": "host-example"}
        self.run_hook("report", "pi", "UserPromptSubmit", payload=payload,
                      environment=dict(self.environment, TERM_PROGRAM="ghostty", __CFBundleIdentifier="unknown.app"))
        path = next((self.directory / "data/events").glob("*.json"))
        self.assertEqual(json.loads(path.read_text())["hostBundleIDHint"], "com.mitchellh.ghostty")
        self.run_hook("report", "pi", "UserPromptSubmit", payload=payload,
                      environment=dict(self.environment, TERM_PROGRAM="unknown", __CFBundleIdentifier="unknown.app"))
        self.assertNotIn("hostBundleIDHint", json.loads(path.read_text()))

    def test_subagents_are_excluded_and_cursor_aborts_are_not_completed(self):
        self.run_hook("report", "claude", "Stop", payload={"session_id": "a", "agent_id": "child"})
        self.assertFalse((self.directory / "data/events").exists())
        payload = {"conversation_id": "cursor-example", "status": "aborted"}
        self.run_hook("report", "cursor", "stop", payload=payload)
        event = json.loads(next((self.directory / "data/events").glob("*.json")).read_text())
        self.assertEqual(event["status"], "unknown")
        result = self.run_hook("report", "cursor", "beforeSubmitPrompt", payload=payload)
        self.assertEqual(json.loads(result.stdout), {"continue": True})

    def test_codex_memory_metadata_is_not_reported_as_an_active_session(self):
        transcript = self.directory / "memory.jsonl"
        transcript.write_text(json.dumps({"type": "session_meta", "payload": {
            "id": "memory-example", "source": {"subagent": "memory_consolidation"}
        }}) + "\n")
        self.run_hook("report", "codex", "Stop", payload={
            "session_id": "memory-example", "transcript_path": str(transcript)
        })
        active = [json.loads(path.read_text()) for path in (self.directory / "data/events").glob("*.json")]
        self.assertFalse([event for event in active if event["status"] != "ended"],
                         "Codex memory consolidation was counted as a completed coding session")

    def test_codex_background_sources_are_excluded_without_agent_id(self):
        sources = [
            {"source": {"subagent": "memory_consolidation"}},
            {"source": {"internal": "memory_consolidation"}},
            {"source": {"internal": "guardian"}},
            {"source": {"subagent": {"thread_spawn": {"parent_thread_id": "parent", "depth": 1}}}},
            *[{"source": "vscode", "thread_source": kind} for kind in
              ("memory_consolidation", "memgen", "memory", "thread_title", "guardian_review")],
        ]
        for index, source in enumerate(sources):
            with self.subTest(source=source):
                session = "background-" + str(index)
                transcript = self.directory / (session + ".jsonl")
                transcript.write_text(json.dumps({"type": "session_meta", "payload": {"id": session, **source}}) + "\n")
                for event in ("UserPromptSubmit", "Stop"):
                    self.run_hook("report", "codex", event, payload={"session_id": session, "transcript_path": str(transcript)})
                # A sparse later event must not restore a known background thread.
                self.run_hook("report", "codex", "Stop", payload={"session_id": session})
        records = [json.loads(path.read_text()) for path in (self.directory / "data/events").glob("*.json")]
        self.assertTrue(records)
        self.assertTrue(all(row["status"] == "ended" for row in records))

    def test_codex_user_sessions_with_memory_in_their_text_stay_visible(self):
        for index, source in enumerate(("cli", "vscode", "exec", "mcp", {"custom": "memory-client"})):
            session = "user-" + str(index)
            transcript = self.directory / (session + ".jsonl")
            transcript.write_text(json.dumps({"type": "session_meta", "payload": {
                "id": session, "source": source, "thread_source": "user", "cwd": "/private/memory",
                "base_instructions": {"text": "PRIVATE memory_consolidation instructions"}
            }}) + "\n" + "PRIVATE TRANSCRIPT CONTENT\n")
            self.run_hook("report", "codex", "UserPromptSubmit", payload={
                "session_id": session, "transcript_path": str(transcript), "cwd": "/private/memory",
                "prompt": "memory_consolidation", "thread_name": "Fix memory consolidation"
            })
            self.run_hook("report", "codex", "Stop", payload={"session_id": session})
        records = [path.read_text() for path in (self.directory / "data/events").glob("*.json")]
        self.assertEqual(len(records), 5)
        self.assertTrue(all(json.loads(row)["status"] == "done" for row in records))
        self.assertTrue(all("PRIVATE" not in row and "transcript_path" not in row and "/private/" not in row for row in records))

    def test_codex_metadata_with_another_id_does_not_end_the_parent(self):
        self.run_hook("report", "codex", "UserPromptSubmit", payload={"session_id": "parent"})
        path = next((self.directory / "data/events").glob("*.json"))
        before = path.read_text()
        transcript = self.directory / "child.jsonl"
        transcript.write_text(json.dumps({"type": "session_meta", "payload": {
            "id": "child", "source": {"internal": "memory_consolidation"}
        }}) + "\n")
        self.run_hook("report", "codex", "Stop", payload={"session_id": "parent", "transcript_path": str(transcript)})
        self.assertEqual(path.read_text(), before)

    def test_codex_metadata_reads_only_a_bounded_regular_file_header(self):
        header = json.dumps({"type": "session_meta", "payload": {
            "id": "unavailable", "source": {"internal": "memory_consolidation"}
        }})
        target = self.directory / "target.jsonl"
        target.write_text(header + "\n")
        symlink = self.directory / "symlink.jsonl"
        symlink.symlink_to(target)
        fifo = self.directory / "fifo"
        os.mkfifo(fifo)
        oversized = self.directory / "oversized.jsonl"
        oversized.write_text(header[:-1] + ', "padding": "' + "x" * 262_144 + '"}\n')
        later = self.directory / "later.jsonl"
        later.write_text('{"type": "response_item", "payload": {}}\n' + header + "\n")
        malformed = self.directory / "malformed.jsonl"
        malformed.write_text("not JSON\n")
        for path in (symlink, fifo, oversized, later, malformed, self.directory / "missing.jsonl"):
            with self.subTest(path=path.name):
                self.run_hook("report", "codex", "UserPromptSubmit", payload={
                    "session_id": "unavailable", "transcript_path": str(path)
                })
                event = json.loads(next((self.directory / "data/events").glob("*.json")).read_text())
                self.assertEqual(event["status"], "working")
                self.assertNotIn("codexSessionKind", event)

    def test_codex_helper_update_hides_matching_legacy_background_reports(self):
        sessions = [("00000000-0000-0000-0000-000000000001", {"internal": "memory_consolidation"}),
                    ("00000000-0000-0000-0000-000000000002", "vscode")]
        for session, source in sessions:
            self.run_hook("report", "codex", "Stop", payload={"session_id": session, "cwd": "/private/memory"})
            transcript = self.directory / "config/.codex/sessions/2026/11/07" / ("rollout-fixture-" + session + ".jsonl")
            transcript.parent.mkdir(parents=True, exist_ok=True)
            transcript.write_text(json.dumps({"type": "session_meta", "payload": {"id": session, "source": source}}) + "\n")
        self.run_hook("install", "codex")
        records = [json.loads(path.read_text()) for path in (self.directory / "data/events").glob("*.json")]
        self.assertEqual(sorted(row["status"] for row in records), ["done", "ended"])
        self.run_hook("report", "codex", "Stop", payload={"session_id": sessions[0][0]})
        records = [json.loads(path.read_text()) for path in (self.directory / "data/events").glob("*.json")]
        self.assertEqual(sorted(row["status"] for row in records), ["done", "ended"])

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


    def test_pi_install_update_remove_preserves_other_extensions(self):
        path = self.directory / "config/.pi/agent/settings.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"theme": "example", "extensions": ["/example/other.ts"]}))
        for _ in range(2):
            self.run_hook("install", "pi")
        value = json.loads(path.read_text())
        self.assertEqual(len(value["extensions"]), 2)
        self.assertEqual(value["extensions"][0], "/example/other.ts")
        self.assertTrue(json.loads(self.run_hook("status", "pi").stdout)["current"])
        extension = self.directory / "data/pi-hook.ts"
        extension.write_text(extension.read_text() + "\n// prior version\n")
        self.assertFalse(json.loads(self.run_hook("status", "pi").stdout)["current"])
        self.run_hook("install", "pi")
        self.assertTrue(json.loads(self.run_hook("status", "pi").stdout)["current"])
        self.run_hook("remove", "pi")
        value = json.loads(path.read_text())
        self.assertEqual(value, {"theme": "example", "extensions": ["/example/other.ts"]})
        self.assertFalse(json.loads(self.run_hook("status", "pi").stdout)["installed"])

    def test_pi_metadata_and_final_outcomes(self):
        payload = {"session_id": "pi-example", "runtime_pid": os.getpid(), "title": "Example\nName", "cwd": "/example/project", "prompt": "PRIVATE PROMPT"}
        for event, status in [("SessionStart", "idle"), ("UserPromptSubmit", "working"), ("PermissionRequest", "blocked"), ("PostToolUse", "working"), ("Stop", "done"), ("Interrupt", "idle"), ("StopFailure", "unknown"), ("SessionEnd", "ended")]:
            self.run_hook("report", "pi", event, payload=payload)
            path = next((self.directory / "data/events").glob("*.json"))
            text = path.read_text()
            value = json.loads(text)
            self.assertEqual(value["status"], status)
            self.assertEqual(value["title"], "ExampleName")
            self.assertEqual(value["runtimePID"], os.getpid())
            self.assertNotIn("PRIVATE", text)
            self.assertNotIn("/example/project", text)

    def test_reports_are_not_suppressed_by_a_multiplexer_environment(self):
        env = dict(self.environment, HERDR_ENV="1")
        self.run_hook("report", "claude", "UserPromptSubmit", payload={"session_id": "example"}, environment=env)
        self.assertEqual(json.loads(next((self.directory / "data/events").glob("*.json")).read_text())["status"], "working")


if __name__ == "__main__":
    unittest.main()
