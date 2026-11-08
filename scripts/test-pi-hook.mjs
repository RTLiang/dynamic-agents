import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const owned = mkdtempSync(join(tmpdir(), "dynamic-agents-pi-"));
process.env.DYNAMIC_AGENTS_DATA_DIR = join(owned, "data");
process.env.DYNAMIC_AGENTS_CONFIG_HOME = join(owned, "config");
try {
    execFileSync("python3", [join(repo, "Sources/AgentCore/Resources/desktop-hook.py"), "install", "pi"]);
    const { default: extension } = await import(pathToFileURL(join(owned, "data/pi-hook.ts")).href);
    const handlers = new Map();
    extension({ on: (name, handler) => handlers.set(name, handler) });
    const ctx = {
        cwd: "/example/project",
        sessionManager: {
            getSessionId: () => "example-pi-session",
            getSessionName: () => "Pi example",
            getEntries: () => { throw new Error("Must not inspect transcript entries"); },
        },
    };
    const emit = async (name, event = {}) => { assert(handlers.has(name)); await handlers.get(name)(event, ctx); };
    const record = () => {
        const directory = join(owned, "data/events");
        return JSON.parse(readFileSync(join(directory, readdirSync(directory).find(name => name.endsWith(".json"))), "utf8"));
    };
    await emit("session_start");
    assert.equal(record().status, "idle");
    await emit("agent_start");
    assert.equal(record().status, "working");
    await emit("ui_prompt_start");
    assert.equal(record().status, "working");
    await emit("ui_prompt_end");
    assert.equal(record().status, "working");
    await emit("turn_end", { outcome: "error", get entries() { throw new Error("Must not read entries"); } });
    assert.equal(record().status, "working", "a low-level failed run may still retry");
    assert(!handlers.has("agent_end"), "low-level run completion must not complete the session");
    await emit("turn_end", { outcome: "completed" });
    await emit("agent_settled", { aborted: false });
    assert.equal(record().status, "done");
    assert.equal(record().runtimePID, process.pid);
    assert.equal(record().title, "Pi example");
    assert.equal(record().project, "project");
    assert(record().ancestorPIDs.includes(process.pid));
    await emit("agent_start");
    await emit("agent_settled", { aborted: true });
    assert.equal(record().status, "idle");
    await emit("agent_start");
    await emit("turn_end", { outcome: "error" });
    await emit("agent_settled", { aborted: false });
    assert.equal(record().status, "unknown");
    await emit("session_shutdown");
    assert.equal(record().status, "ended");
    console.log("PASS: Pi lifecycle extension → copied Python reporter → private metadata, retry/abort/error/shutdown boundaries");
} finally {
    execFileSync("trash", [owned]);
}
