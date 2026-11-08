#!/usr/bin/env python3
"""Local lifecycle bridge. Stores session metadata, never prompts or tool payloads."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import time

SOURCES = {
    "pi": (".pi/agent/settings.json", []),
    "claude": (".claude/settings.json", ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "StopFailure", "SessionEnd"]),
    "codex": (".codex/hooks.json", ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"]),
    "cursor": (".cursor/hooks.json", ["sessionStart", "beforeSubmitPrompt", "afterAgentThought", "stop", "sessionEnd"]),
    "copilot": (".copilot/hooks/dynamic-agents.json", ["sessionStart", "userPromptSubmitted", "postToolUse", "agentStop", "sessionEnd"]),
}
ROOT = Path(os.environ.get("DYNAMIC_AGENTS_DATA_DIR", Path.home() / "Library/Application Support/DynamicAgents"))
HOME = Path(os.environ.get("DYNAMIC_AGENTS_CONFIG_HOME", Path.home()))
MARKER = "dynamic-agents-hook-v1"


def private_directory(path):
    if path.is_symlink():
        raise ValueError("Refusing a symlinked bridge directory")
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.stat().st_uid != os.getuid():
        raise ValueError("Bridge directory is not owned by this user")
    path.chmod(0o700)


def atomic_json(path, value):
    if path.is_symlink():
        raise ValueError("Refusing a symlinked file")
    temporary = path.with_name(path.name + ".pending-" + str(os.getpid()))
    with temporary.open("x", encoding="utf-8") as handle:
        os.chmod(temporary, 0o600)
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(temporary, path)


def config_path(source):
    overrides = {"pi": "PI_CODING_AGENT_DIR", "claude": "CLAUDE_CONFIG_DIR", "codex": "CODEX_HOME", "cursor": "CURSOR_CONFIG_DIR", "copilot": "COPILOT_HOME"}
    if os.environ.get(overrides[source]) and "DYNAMIC_AGENTS_CONFIG_HOME" not in os.environ:
        base = Path(os.environ[overrides[source]])
        name = {"pi": "settings.json", "claude": "settings.json", "codex": "hooks.json", "cursor": "hooks.json", "copilot": "hooks/dynamic-agents.json"}[source]
        return base / name
    return HOME / SOURCES[source][0]


def owned_command(command):
    try:
        words = shlex.split(command)
    except (TypeError, ValueError):
        return False
    return len(words) == 6 and words[:3] == ["python3", str(ROOT / "desktop-hook.py"), "report"] and words[-1] == MARKER


def managed(entry):
    if not isinstance(entry, dict):
        return False
    commands = entry.get("hooks", [entry])
    return any(isinstance(x, dict) and owned_command(x.get("command", "")) for x in commands)


def configure_pi(action):
    path = config_path("pi")
    if path.is_symlink():
        raise ValueError("Refusing a symlinked Pi configuration")
    original = path.read_bytes() if path.exists() else None
    value = json.loads(original) if original else {}
    if not isinstance(value, dict) or not isinstance(value.get("extensions", []), list):
        raise ValueError("Unsupported Pi extensions configuration")
    extension = ROOT / "pi-hook.ts"
    script = ROOT / "desktop-hook.py"
    entries = value.get("extensions", [])
    installed = str(extension) in entries and script.is_file() and not script.is_symlink() and extension.is_file() and not extension.is_symlink()
    current = installed and script.read_bytes() == Path(__file__).read_bytes() and extension.read_bytes() == Path(__file__).with_name("pi-hook.ts").read_bytes()
    if action == "status":
        print(json.dumps({"installed": installed, "current": current}))
        return
    private_directory(ROOT)
    private_directory(ROOT / "events")
    if script.is_symlink() or extension.is_symlink():
        raise ValueError("Refusing a symlinked Pi bridge")
    if action == "install":
        script.write_bytes(Path(__file__).read_bytes())
        script.chmod(0o700)
        extension.write_bytes(Path(__file__).with_name("pi-hook.ts").read_bytes())
        extension.chmod(0o600)
    value["extensions"] = [entry for entry in entries if entry != str(extension)]
    if action == "install":
        value["extensions"].append(str(extension))
    path.parent.mkdir(parents=True, exist_ok=True)
    if original is not None:
        backup = path.with_name(path.name + ".dynamic-agents-backup-" + str(time.time_ns()))
        with backup.open("xb") as handle:
            handle.write(original)
        backup.chmod(0o600)
    atomic_json(path, value)
    enabled_path = ROOT / "sources.json"
    enabled = json.loads(enabled_path.read_text()) if enabled_path.exists() and not enabled_path.is_symlink() else {}
    enabled["pi"] = action == "install"
    atomic_json(enabled_path, enabled)
    print(json.dumps({"installed": action == "install", "current": action == "install"}))


def configure(source, action):
    if source == "pi":
        configure_pi(action)
        return
    path = config_path(source)
    if path.is_symlink():
        raise ValueError("Refusing a symlinked hook configuration")
    original = path.read_bytes() if path.exists() else None
    value = json.loads(original) if original else {}
    hooks = value.get("hooks", {})
    if not isinstance(value, dict) or not isinstance(hooks, dict):
        raise ValueError("Unsupported hook configuration")
    if source in ("cursor", "copilot") and value.get("version", 1) != 1:
        raise ValueError("Unsupported hook configuration version")
    installed = all(any(managed(x) for x in hooks.get(event, [])) for event in SOURCES[source][1])
    script = ROOT / "desktop-hook.py"
    installed = installed and script.is_file() and not script.is_symlink()
    current = installed and script.read_bytes() == Path(__file__).read_bytes()
    if action == "status":
        print(json.dumps({"installed": installed, "current": current}))
        return
    private_directory(ROOT)
    private_directory(ROOT / "events")
    script = ROOT / "desktop-hook.py"
    if action == "install":
        text = Path(__file__).read_text()
        if script.is_symlink():
            raise ValueError("Refusing a symlinked bridge script")
        script.write_text(text)
        script.chmod(0o700)
    for event in SOURCES[source][1]:
        entries = hooks.get(event, [])
        if not isinstance(entries, list):
            raise ValueError("Unsupported hook event configuration")
        retained = []
        for entry in entries:
            if not managed(entry):
                retained.append(entry)
            elif isinstance(entry.get("hooks"), list):
                remaining = [x for x in entry["hooks"] if not (isinstance(x, dict) and owned_command(x.get("command", "")))]
                if remaining:
                    retained.append({**entry, "hooks": remaining})
        if action == "install":
            command = "python3 " + shlex.quote(str(script)) + " report " + source + " " + event + " " + MARKER
            handler = {"type": "command", "command": command}
            if source in ("claude", "codex"):
                handler["timeout"] = 2
                retained.append({"hooks": [handler]})
            else:
                handler["timeoutSec" if source == "copilot" else "timeout"] = 2
                retained.append(handler)
        if retained:
            hooks[event] = retained
        else:
            hooks.pop(event, None)
    value["hooks"] = hooks
    if source in ("cursor", "copilot"):
        value.setdefault("version", 1)
    path.parent.mkdir(parents=True, exist_ok=True)
    if original is not None:
        backup = path.with_name(path.name + ".dynamic-agents-backup-" + str(time.time_ns()))
        with backup.open("xb") as handle:
            handle.write(original)
        backup.chmod(0o600)
    atomic_json(path, value)
    enabled_path = ROOT / "sources.json"
    enabled = json.loads(enabled_path.read_text()) if enabled_path.exists() and not enabled_path.is_symlink() else {}
    enabled[source] = action == "install"
    atomic_json(enabled_path, enabled)
    if source == "codex" and action == "install":
        reconcile_codex_reports()
    print(json.dumps({"installed": action == "install", "current": action == "install"}))


def host_app_hint():
    programs = {"ghostty": "com.mitchellh.ghostty", "iterm.app": "com.googlecode.iterm2", "apple_terminal": "com.apple.Terminal", "vscode": "com.microsoft.VSCode", "cursor": "com.todesktop.230313mzl4w4u92", "wezterm": "com.github.wez.wezterm", "warpterminal": "dev.warp.Warp-Stable"}
    bundle = os.environ.get("__CFBundleIdentifier", "")
    if bundle in set(programs.values()) | {"com.openai.codex", "com.anthropic.claudefordesktop"}:
        return bundle
    return programs.get(os.environ.get("TERM_PROGRAM", "").lower())


def ancestry():
    result = subprocess.run(["/bin/ps", "-axo", "pid=,ppid="], capture_output=True, text=True, timeout=0.4)
    parents = {}
    for line in result.stdout.splitlines():
        values = line.split()
        if len(values) == 2:
            parents[int(values[0])] = int(values[1])
    pid = os.getppid()
    chain = []
    while pid > 1 and pid not in chain and len(chain) < 40:
        chain.append(pid)
        pid = parents.get(pid, 0)
    return chain


def project_name(source, payload):
    cwd = payload.get("cwd")
    if isinstance(cwd, str):
        roots = [cwd]
    elif source == "cursor" and isinstance(payload.get("workspace_roots"), list):
        roots = payload["workspace_roots"]
    else:
        return None
    names = []
    for root in roots:
        if not isinstance(root, str) or not root:
            continue
        name = "".join(c for c in Path(root).name if ord(c) >= 32)
        if name and name not in names:
            names.append(name)
    return ", ".join(names)[:120]


def codex_metadata(path):
    if not isinstance(path, str) or not path or len(path) > 4096:
        return None
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as handle:
            info = os.fstat(handle.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                return None
            line = handle.readline(262_145)
        if len(line) > 262_144:
            return None
        row = json.loads(line)
        if not isinstance(row, dict) or row.get("type") != "session_meta":
            return None
        metadata = row.get("payload")
        if not isinstance(metadata, dict) or not isinstance(metadata.get("id"), str):
            return None
        source = metadata.get("source")
        thread_source = metadata.get("thread_source")
        background = (isinstance(source, dict) and ("subagent" in source or "internal" in source)
                      or isinstance(source, str) and source in ("memory_consolidation", "memgen", "memory")
                      or isinstance(thread_source, str) and thread_source not in ("", "user"))
        return metadata["id"], bool(background)
    except (OSError, ValueError):
        return None


def reconcile_codex_reports():
    directory = ROOT / "events"
    reports = {}
    for path in directory.glob("*.json"):
        try:
            info = path.lstat()
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size >= 8192:
                continue
            value = json.loads(path.read_bytes())
            if isinstance(value, dict) and value.get("source") == "codex" and value.get("id") == path.stem:
                reports[path.stem] = path
        except (OSError, ValueError):
            continue
    if not reports:
        return
    classifications = {}
    sessions = config_path("codex").parent / "sessions"
    for path in sessions.glob("*/*/*/rollout-*.jsonl"):
        session = path.stem[-36:]
        key = hashlib.sha256(("codex:" + session).encode()).hexdigest()
        if key not in reports:
            continue
        metadata = codex_metadata(str(path))
        if metadata is not None and metadata[0] == session:
            classifications[key] = "background" if metadata[1] else "user"
    for key, report_path in reports.items():
        lock_path = directory / (key + ".lock")
        if lock_path.is_symlink():
            continue
        try:
            with lock_path.open("a") as lock:
                os.chmod(lock_path, 0o600)
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                if report_path.is_symlink():
                    continue
                value = json.loads(report_path.read_bytes())
                if not isinstance(value, dict) or value.get("id") != key or value.get("source") != "codex":
                    continue
                previous = value.get("codexSessionKind")
                kind = "background" if previous == "background" else classifications.get(key, previous if previous == "user" else "unverified")
                value["codexSessionKind"] = kind
                if kind != "user":
                    value.update(status="ended", ancestorPIDs=[])
                    value.pop("completedAt", None)
                atomic_json(report_path, value)
        except (OSError, ValueError):
            continue


def report(source, event):
    if source not in SOURCES:
        return
    enabled_path = ROOT / "sources.json"
    if enabled_path.exists() and json.loads(enabled_path.read_text()).get(source) is False:
        return
    payload = json.loads(sys.stdin.buffer.read(1_048_576))
    if not isinstance(payload, dict) or payload.get("agent_id") or payload.get("agentId"):
        return
    if source == "cursor":
        session = payload.get("conversation_id") or payload.get("session_id")
    else:
        session = payload.get("session_id") or payload.get("sessionId")
    if not isinstance(session, str) or not session or len(session) > 256:
        return
    session_kind = "unverified" if source == "codex" else None
    if source == "codex":
        metadata = codex_metadata(payload.get("transcript_path"))
        if metadata is not None:
            if metadata[0] != session:
                return
            session_kind = "background" if metadata[1] else "user"
    if event in ("SessionEnd", "sessionEnd"):
        status = "ended"
    elif event in ("SessionStart", "sessionStart", "Interrupt"):
        status = "idle"
    elif event in ("Stop", "agentStop", "stop"):
        if source == "cursor" and payload.get("status") != "completed":
            status = "unknown"
        else:
            status = "done"
    elif event == "StopFailure":
        status = "unknown"
    elif event == "PermissionRequest":
        status = "blocked"
    else:
        status = "working"
    now = time.time()
    received = time.time_ns()
    project = project_name(source, payload)
    private_directory(ROOT)
    directory = ROOT / "events"
    private_directory(directory)
    key = hashlib.sha256((source + ":" + session).encode()).hexdigest()
    path = directory / (key + ".json")
    lock_path = directory / (key + ".lock")
    if lock_path.is_symlink():
        return
    with lock_path.open("a") as lock:
        os.chmod(lock_path, 0o600)
        deadline = time.monotonic() + 0.5
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    return
                time.sleep(0.01)
        old = json.loads(path.read_text()) if path.exists() and not path.is_symlink() else {}
        if int(old.get("sequence", 0)) >= received:
            return
        if source == "codex":
            previous_kind = old.get("codexSessionKind")
            if previous_kind == "background" or session_kind == "unverified" and previous_kind == "user":
                session_kind = previous_kind
            if session_kind != "user":
                status = "ended"
        if status == "idle" and old.get("status") in ("working", "blocked") and event in ("SessionStart", "sessionStart"):
            return
        if project is None:
            previous = old.get("project", "")
            project = previous if isinstance(previous, str) else ""
        record = {"id": key, "source": source, "status": status, "sequence": received,
                  "timestamp": now, "project": project[:120],
                  "ancestorPIDs": [] if session_kind in ("background", "unverified") else ancestry()}
        hint = host_app_hint()
        if hint is not None:
            record["hostBundleIDHint"] = hint
        previous_completion = old.get("completedAt", old.get("timestamp") if old.get("status") == "done" else None)
        if not isinstance(previous_completion, (int, float)) or isinstance(previous_completion, bool) or not 0 <= previous_completion <= now:
            previous_completion = None
        if status == "done":
            record["completedAt"] = previous_completion if old.get("status") == "done" and previous_completion is not None else now
        elif status in ("idle", "ended") and event != "Interrupt" and session_kind not in ("background", "unverified") and previous_completion is not None:
            record["completedAt"] = previous_completion
        if source == "pi":
            title = payload.get("title")
            if isinstance(title, str):
                record["title"] = "".join(c for c in title if ord(c) >= 32)[:240]
            runtime = payload.get("runtime_pid")
            if isinstance(runtime, int) and not isinstance(runtime, bool) and runtime > 1:
                record["runtimePID"] = runtime
        if session_kind is not None:
            record["codexSessionKind"] = session_kind
        atomic_json(path, record)


if __name__ == "__main__":
    reporting = len(sys.argv) >= 4 and sys.argv[1] == "report"
    try:
        if reporting:
            report(sys.argv[2], sys.argv[3])
        else:
            action, source = sys.argv[1:3]
            if source not in SOURCES or action not in ("status", "install", "remove"):
                raise ValueError("Unsupported action or agent")
            configure(source, action)
    except Exception as error:
        if not reporting:
            print(str(error), file=sys.stderr)
            sys.exit(1)
    if reporting:
        print(json.dumps({"continue": True} if sys.argv[2] == "cursor" and sys.argv[3] == "beforeSubmitPrompt" else {}))
