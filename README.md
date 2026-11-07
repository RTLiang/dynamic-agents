# Dynamic Agents

macOS SwiftUI 应用，通过 [herdr](https://herdr.dev/) 查看 coding agent 状态，并在系统实时活动中快速切回终端。

## 功能

- 显示 herdr 检测到的 Pi、Claude Code、Codex 等 agent，也支持自定义 agent 类型。
- 在连接设置中管理 herdr 的 Agent 集成：查看可用性和安装状态，安装、更新或移除 Hook/插件，并区分生命周期上报与 herdr 状态检测。
- 独立的桌面 Hook 通道接收 Claude Code Desktop、Codex App、Cursor 和 VS Code Copilot 本机编程会话事件，支持 herdr 之外的会话。按需安装，不自动改写客户端配置。
- Codex 会话有可用标题时优先显示标题，并同步改名；没有标题时回退为 agent 类型与会话短码。
- 主窗口提供搜索、状态筛选、排序和终端定位；按 herdr session、客户端 PID 和 TTY 区分同一终端 App 的多个窗口，无需手动填写 Bundle ID。首次打开 agent 创建独立直连视图，再次点击复用，不广播切换其他 herdr 窗口。
- 使用 ActivityKit 和 WidgetKit 展示系统实时活动。收起时显示运行和完成数量，展开时逐条显示会话；点击会话通过后台 App Intent 打开终端或桌面宿主 App。
- 实时活动只包含运行中的 agent 和最近完成的 agent。完成后保留时间可在设置中调整为 **1–1440 分钟**，默认 10 分钟；没有符合条件的 agent 时自动隐藏。
- 菜单栏图标可单独隐藏，App 和实时活动继续运行。可从 Dock 重新打开主窗口，并在设置中恢复图标。
- 支持 English 和简体中文，跟随系统或 macOS 的单应用语言设置。
- App 菜单与设置提供检查更新，可自动每日检查 GitHub 稳定 Release；标签触发的 CI 构建原生 ZIP 和 SHA-256，不执行公证。

## 要求

- 本机运行的 herdr；当前协议适配经 herdr 0.9.5 验证。
- 实时活动版本需要 macOS 27.3+ 和对应 SDK 的 Xcode。
- 桌面 Hook 需要本机可用的 Python 3；客户端版本、Hook 信任设置或组织策略会影响是否上报。
- SwiftPM Companion 版本需要 macOS 15+，但不包含实时活动。
- 精确终端定位支持 Ghostty 1.3+、iTerm2 和 Apple Terminal，需要允许 App 的自动化请求。

系统决定实时活动的展示位置与可用空间。未配置或未能检测的 agent 取决于 herdr 的支持和集成配置；详见 [herdr 文档](https://herdr.dev/docs/agents/)。

## 安装与构建

```bash
# 原生版本：构建、安装、注册 Widget 并打开
bash scripts/install-app.sh

# 仅构建原生 App 和 Widget
bash scripts/build-app.sh native

# 构建不含 Widget 的 Companion
bash scripts/build-app.sh companion
```

安装脚本默认使用用户 Applications 目录；如果仅在系统 Applications 目录中已有本 App，则更新该安装。更新时旧安装移入废纸篓，脚本需要 `trash` 命令。它自动寻找满足要求的 SDK，不修改全局 Xcode 选择；显式指定 `DEVELOPER_DIR` 时使用指定工具链。

构建产物位于 `dist/`。应用使用 ad-hoc 签名，不执行公证。推送稳定版本标签可通过 GitHub Actions 发布原生包；构建 runner 必须提供 27.3 SDK。工作流、runner 配置及更新源见 [Release 与检查更新](docs/RELEASES.md)。Xcode 项目由 `scripts/generate-project.py` 生成，若需开发者签名请在生成后自行配置团队。

## 使用

1. 在终端启动 herdr，并在其中启动 agent。
2. 打开 Dynamic Agents。默认自动发现 herdr 可执行文件；也可在连接设置中指定路径和会话。
3. 主窗口单击选择 agent，双击或按 Return 打开对应 session 的 agent 直连视图；桌面 Hook 会话定位其终端或激活桌面宿主。多个 herdr 客户端时，在设置中选择具体“herdr 窗口”。Ghostty / iTerm2 在所选窗口新建标签，Apple Terminal 新建独立窗口。
4. 在工具栏控制实时活动。连接设置中的“完成后保留”可设置分钟数，保存后立即生效。
5. 在连接设置 → Agent 集成 → 管理集成中，按需安装或更新对应 agent 的集成，完成后重启那个 agent。安装/移除立即生效，不受设置页保存或取消影响。
6. 菜单栏菜单可隐藏菜单栏图标；在连接设置中可以恢复。关闭主窗口不会退出 App。

herdr 的集成只服务于 herdr 中的会话。桌面客户端可使用管理页中的“桌面客户端”标签安装独立 Hook，重启客户端并完成信任审核后接收本机任务事件；不监控普通聊天窗口或仅凭进程判断忙碌。详见 [桌面 Hook](docs/DESKTOP-HOOKS.md) 和 [herdr 调研](docs/HERDR-AGENT-MONITORING.md)。

完成时刻依据 herdr 的 `completion_seq` 或状态变化在持续轮询时记录。首次连接或长时间中断后，无法确定时间的旧完成记录不会当成新完成任务。调整时长不会改变原始 herdr 状态。[详细说明](docs/NATIVE-UI-AND-AGENTS.md)。

## 测试

```bash
python3 scripts/check-localizations.py
python3 scripts/test-desktop-hooks.py
swift test --build-system native
# 可选：对当前 herdr 执行只读集成测试
HERDR_LIVE_TEST=1 swift test --build-system native
```

核心测试覆盖快照解析、agent 类型、集成管理 API、Unix Socket 通信、可配置完成时长、载荷限制、超时、终端窗口与 session 隔离、稳定版本更新解析和本地化。原生实时活动和后台跳转的实机验证方式见 [验证说明](docs/NATIVE-VERIFICATION.md) 与 [后台终端跳转](docs/BACKGROUND-HANDOFF.md)。完整系统 Widget 的鼠标点击和具体展示方式仍需在目标系统上手动确认。

## 结构

- `Sources/AgentCore/`：herdr 协议、终端发现、状态、活动载荷和本地化资源。
- `Sources/DynamicAgents/`：SwiftUI 主程序、实时活动生命周期和后台动作。
- `WidgetExtension/`：WidgetKit 和系统实时活动视图。
- `Tests/AgentCoreTests/`：核心模型及集成测试。
- `scripts/`：构建、安装、项目生成与检查。

更多信息：[终端检测](docs/TERMINAL-DETECTION.md) · [多 Agent 与显示规则](docs/NATIVE-UI-AND-AGENTS.md) · [本地化](docs/LOCALIZATION.md) · [API 参考](docs/API-REFERENCES.md)。
