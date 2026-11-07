# 原生界面与多 Agent 接入

## 界面

主窗口采用 SwiftUI 原生表格和菜单栏菜单；支持搜索、状态筛选、排序以及用鼠标或键盘打开终端。默认按运行中、需要输入、最近已完成、空闲、未知排序，菜单采用相同顺序。菜单栏图标可单独隐藏，App 和实时活动继续运行。连接设置中可调整完成后保留时间，范围为 1–1440 分钟，默认 10 分钟。

实时活动收起时按状态显示数量；展开时逐条显示符合条件的 agent 和状态。系统空间和载荷有限时，剩余项可在主窗口查看。没有符合条件的 agent 或连接断开时活动隐藏，重新出现符合条件的 agent 后恢复。

设计参考 Apple 的 [macOS 指南](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)、[列表与表格](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)、[工具栏](https://developer.apple.com/design/human-interface-guidelines/toolbars)、[Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)和[应用图标](https://developer.apple.com/design/human-interface-guidelines/app-icons)。

## herdr 接入

App 读取 herdr 的快照，不自行推断 agent 状态；终端跳转使用 herdr pane ID。herdr 0.9.5 的内置类型覆盖 Pi、Claude Code、Codex、Gemini、OpenCode 等；其他非空自报类型也会保留，不依赖固定白名单。

类型显示名与原始类型分开；herdr 的自定义名称和 `display_agent` 仅影响显示，不改变 pane 身份和语义状态。普通 shell 不进入 agent 列表。参考 [herdr Agent 文档](https://herdr.dev/docs/agents/)、[集成文档](https://herdr.dev/docs/integrations/)和 [AgentInfo 源码](https://github.com/herdrdev/herdr/blob/v0.9.5/src/api/schema/agents.rs)。

## 完成时间

herdr 的 `completion_seq` 标记完成，但不提供完成时刻。App 在连续轮询中观察到完成时记录时间；查看后上游状态变回 `idle` 时，主窗口、菜单和实时活动仍在提醒期内显示已完成。首次连接或长时间中断后，无法确认完成时刻的旧记录不会被误判为刚完成。已完成描述一轮执行结束，不代表整个项目完成或成功。

提醒到期后，仍可用的会话显示为空闲；旧桌面记录若没有经验证的活跃宿主和运行时便隐藏，避免把已经关闭的会话显示为 Idle。新建、待输入前的普通空闲以及中断都不能单凭“没有工作”创建完成提醒。

展示时长可调，默认 10 分钟；修改后立即重新计算。已知的完成时刻最多保留 24 小时，以便延长设置时重新显示仍在新范围内的会话。首次连接之前的完成时间无法恢复。

## 验证边界

核心测试覆盖多 agent 快照、显示覆盖、完成时间、过滤与载荷限制。原生生命周期验证和后台跳转验证的运行方式见 [实时活动验证](NATIVE-VERIFICATION.md) 和 [后台跳转](BACKGROUND-HANDOFF.md)。运行这些验证需要本地 herdr、受支持的 macOS 和终端会话；本机截图和运行报告不包含在公开仓库中。
