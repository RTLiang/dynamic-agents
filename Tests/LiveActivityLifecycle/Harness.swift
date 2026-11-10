import ActivityKitTestDouble
import Foundation

@MainActor final class TestClock {
    var date = Date(timeIntervalSince1970: 1000)
    func advance(_ seconds: Double) { date = date.addingTimeInterval(seconds) }
}

@main
struct LifecycleTests {
    @MainActor static func main() async throws {
        let domain = Bundle.main.bundleIdentifier!
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let agent = Agent(hookID: String(repeating: "a", count: 64), kind: "pi", title: "Example", project: "Example", status: .working, completedAt: nil, hostBundleID: "example.host")
        let feed = AgentActivityState(agents: [agent])
        var results: [[String: Any]] = []
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "LifecycleTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func run(_ name: String, _ body: @MainActor (TestClock) async throws -> Void) async {
            FakeActivitySystem.reset()
            UserDefaults.standard.removePersistentDomain(forName: domain)
            do {
                try await body(TestClock())
                results.append(["case": name, "passed": true])
                print("PASS: " + name)
            } catch {
                results.append(["case": name, "passed": false, "error": error.localizedDescription])
                print("FAIL: " + name + ": " + error.localizedDescription)
            }
        }
        await run("lost registry recreates while preference remains enabled") { clock in
            let c = LiveActivityController(now: { clock.date })
            await c.start(state: feed)
            FakeActivitySystem.loseRegistry()
            clock.advance(6)
            await c.update(feed)
            try check(FakeActivitySystem.requests == 1, "recreated before confirming a missing registry entry")
            await c.update(feed)
            try check(c.isEnabled && c.isRunning && FakeActivitySystem.requests == 2 && FakeActivitySystem.instances.count == 1, "enabled Working feed has no system activity")
            await c.stop()
        }
        await run("transient registry gap keeps existing activity") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            let original = FakeActivitySystem.instances[0]
            FakeActivitySystem.loseRegistry(); clock.advance(6); await c.update(feed)
            FakeActivitySystem.instances = [original]; await c.update(feed)
            try check(FakeActivitySystem.requests == 1 && c.isRunning, "transient gap recreated the activity")
            await c.stop()
        }
        await run("new requests have a registry propagation grace period") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            let original = FakeActivitySystem.instances[0]; FakeActivitySystem.loseRegistry()
            for _ in 0..<4 { await c.update(feed) }
            try check(FakeActivitySystem.requests == 1, "new activity was recreated during propagation")
            FakeActivitySystem.instances = [original]; await c.stop()
        }
        await run("system ended event preserves intent and restarts") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            (FakeActivitySystem.instances[0] as! Activity<AgentActivityAttributes>).transition(.ended)
            for _ in 0..<5 { await Task.yield() }
            try check(c.isEnabled && UserDefaults.standard.bool(forKey: "liveActivityEnabled"), "system end disabled the user's preference")
            clock.advance(3); await c.update(feed)
            try check(c.isRunning && FakeActivitySystem.requests == 2, "system end never recreated")
            await c.stop()
        }
        await run("ended state recovers even before its observer executes") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            (FakeActivitySystem.instances[0] as! Activity<AgentActivityAttributes>).activityState = .ended
            await c.update(feed)
            try check(c.isEnabled && c.isRunning && FakeActivitySystem.requests == 2, "synchronous end disabled recovery")
            await c.stop()
        }
        await run("explicit dismissal remains disabled") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            (FakeActivitySystem.instances[0] as! Activity<AgentActivityAttributes>).transition(.dismissed)
            for _ in 0..<5 { await Task.yield() }
            clock.advance(60); await c.update(feed)
            try check(!c.isEnabled && !UserDefaults.standard.bool(forKey: "liveActivityEnabled") && FakeActivitySystem.requests == 1, "dismissal was automatically undone")
            await c.stop()
        }
        await run("explicit enable works after a dismissal") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            (FakeActivitySystem.instances[0] as! Activity<AgentActivityAttributes>).activityState = .dismissed
            await c.start(state: feed)
            try check(c.isEnabled && c.isRunning && FakeActivitySystem.requests == 2, "explicit enable remained dismissed")
            await c.stop()
        }
        await run("empty feeds hide without disabling later starts") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            await c.update(AgentActivityState(agents: []))
            try check(c.isEnabled && !c.isRunning, "empty feed disabled monitoring")
            await c.update(feed)
            try check(c.isRunning && FakeActivitySystem.requests == 2, "new eligible feed never restarted")
            await c.stop()
        }
        await run("request failures retry with bounded backoff") { clock in
            FakeActivitySystem.failures = 2
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            for _ in 0..<5 { await c.update(feed) }
            try check(FakeActivitySystem.requests == 1 && c.message != nil && c.isEnabled, "failed request floods or disables updates")
            clock.advance(2); await c.update(feed)
            try check(FakeActivitySystem.requests == 2, "first retry missing")
            clock.advance(3); await c.update(feed)
            try check(FakeActivitySystem.requests == 2, "second retry occurred early")
            clock.advance(1); await c.update(feed)
            try check(c.isRunning && c.message == nil && FakeActivitySystem.requests == 3, "successful retry did not recover")
            await c.stop()
        }
        await run("foreground activation retries pending failures immediately") { clock in
            FakeActivitySystem.failures = 1
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            await c.retryIfNeeded(state: feed)
            try check(c.isEnabled && c.isRunning && FakeActivitySystem.requests == 2, "foreground activation waited for the background backoff")
            await c.stop()
        }
        await run("cold background visibility rejection waits for foreground") { clock in
            FakeActivitySystem.visibilityFailures = 1
            var foreground = false
            let c = LiveActivityController(now: { clock.date }, isForeground: { foreground })
            await c.start(state: feed)
            clock.advance(60)
            for _ in 0..<5 { await c.update(feed) }
            try check(c.isEnabled && !c.isRunning && c.message != nil && FakeActivitySystem.requests == 1, "background visibility failure was hidden or repeatedly requested")
            foreground = true
            await c.retryIfNeeded(state: feed)
            try check(c.isRunning && c.message == nil && FakeActivitySystem.requests == 2, "foreground activation did not recover visibility rejection")
            await c.stop()
        }
        await run("foreground visibility propagation still retries with backoff") { clock in
            FakeActivitySystem.visibilityFailures = 2
            var foreground = false
            let c = LiveActivityController(now: { clock.date }, isForeground: { foreground })
            await c.start(state: feed)
            foreground = true
            await c.retryIfNeeded(state: feed)
            try check(!c.isRunning && FakeActivitySystem.requests == 2, "second visibility rejection was not retained")
            clock.advance(4); await c.update(feed)
            try check(c.isRunning && c.message == nil && FakeActivitySystem.requests == 3, "visibility propagation delay permanently blocked foreground creation")
            await c.stop()
        }
        await run("authorization restoration recovers without toggling") { clock in
            FakeActivitySystem.authorized = false
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            try check(c.isEnabled && !c.isRunning && FakeActivitySystem.requests == 0, "unauthorized request reached backend")
            FakeActivitySystem.authorized = true; clock.advance(5); await c.update(feed)
            try check(c.isRunning && FakeActivitySystem.requests == 1, "authorization restoration never started")
            await c.stop()
        }
        await run("explicit restart replaces exactly one activity") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            let id = c.status?.activityID
            await c.restart(state: feed)
            try check(c.isEnabled && c.isRunning && c.status?.activityID != id && c.status?.activeCount == 1 && FakeActivitySystem.requests == 2, "explicit restart failed or duplicated activities")
            await c.stop()
        }
        await run("unchanged updates retain their heartbeat") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            for _ in 0..<5 { await c.update(feed) }
            try check(FakeActivitySystem.requests == 1 && FakeActivitySystem.updates == 0, "unchanged feed updated too often")
            clock.advance(30); await c.update(feed)
            try check(FakeActivitySystem.updates == 1 && (c.status?.staleDate?.timeIntervalSince(clock.date) ?? 0) == 90, "heartbeat failed to refresh stale date")
            await c.stop()
        }
        await run("stop during recovery cannot recreate an activity") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            FakeActivitySystem.loseRegistry(); clock.advance(6); await c.update(feed)
            FakeActivitySystem.pauseNextEnd = true
            let update = Task { await c.update(feed) }
            for _ in 0..<50 {
                if FakeActivitySystem.endPaused { break }
                await Task.yield()
            }
            let didPause = FakeActivitySystem.endPaused
            await c.stop()
            FakeActivitySystem.resumeEnd()
            await update.value
            try check(didPause && !c.isEnabled && !c.isRunning && FakeActivitySystem.requests == 1 && c.status?.activeCount == 0, "interrupted recovery recreated after manual stop")
        }
        await run("manual stop prevents later automatic starts") { clock in
            let c = LiveActivityController(now: { clock.date }); await c.start(state: feed)
            await c.stop(); clock.advance(60); await c.update(feed)
            try check(!c.isEnabled && !c.isRunning && FakeActivitySystem.requests == 1 && c.status?.activeCount == 0, "manual stop was ignored")
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        if !results.allSatisfy({ $0["passed"] as? Bool == true }) { exit(1) }
    }
}
