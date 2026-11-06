# 后台终端跳转

实时活动中的 agent 行使用 `Button(intent: FocusAgentIntent(...))`。动作声明 `.background` 模式与主 App 执行目标，沿用应用的 pane 聚焦、终端发现与错误处理，不先打开主窗口。旧的 agent URL 仅保留兼容。

验证模式只重新聚焦当前选中的 agent，不发送输入。它先激活终端，再直接执行同一个 intent，并通过激活通知检查 App 是否出现在前台：

```bash
bash scripts/install-app.sh --verify-live-activity "$PWD/.build/handoff-check.json"
```

验证同时检查后台 App Intent 元数据。直接调用 `perform()` 不能证明系统 Widget 鼠标点击的完整分发路径；需要单独在目标系统上手动测试。

macOS 27.3 SDK 中 `LiveActivityIntent` 不可用于 macOS，因此使用 `AppIntent`；详见 [Apple 的主进程执行目标](https://developer.apple.com/documentation/appintents/intentexecutiontargets/main)。
