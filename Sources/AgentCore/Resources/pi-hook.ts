// Dynamic Agents Pi lifecycle bridge: dynamic-agents-pi-v1
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export default function (pi: ExtensionAPI) {
    const reporter = join(dirname(fileURLToPath(import.meta.url)), "desktop-hook.py");
    let running = false;
    let outcome = "completed";
    let queue = Promise.resolve();
    const report = (event: string, ctx: ExtensionContext) => {
        const payload = JSON.stringify({
            session_id: ctx.sessionManager.getSessionId(),
            cwd: ctx.cwd,
            title: ctx.sessionManager.getSessionName(),
            runtime_pid: process.pid,
        });
        queue = queue.then(() => new Promise<void>((resolve) => {
            const child = execFile("python3", [reporter, "report", "pi", event],
                { timeout: 1500, maxBuffer: 8192 }, () => resolve());
            child.on("error", () => resolve());
            child.stdin?.on("error", () => {});
            child.stdin?.end(payload);
        }));
        return queue;
    };
    pi.on("session_start", async (_event, ctx) => { await report("SessionStart", ctx); });
    pi.on("agent_start", async (_event, ctx) => {
        running = true;
        outcome = "completed";
        await report("UserPromptSubmit", ctx);
    });
    pi.on("turn_end", (event) => { outcome = event.outcome; });
    pi.on("ui_prompt_start", async (_event, ctx) => { if (running) await report("PermissionRequest", ctx); });
    pi.on("ui_prompt_end", async (_event, ctx) => { if (running) await report("PostToolUse", ctx); });
    pi.on("agent_settled", async (event, ctx) => {
        running = false;
        await report(event.aborted || outcome === "aborted" ? "Interrupt" : outcome === "error" ? "StopFailure" : "Stop", ctx);
    });
    pi.on("session_shutdown", async (_event, ctx) => { running = false; await report("SessionEnd", ctx); });
}
