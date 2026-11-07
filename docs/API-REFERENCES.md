# API 依据与参考

## Apple API

- [ActivityKit Activity](https://developer.apple.com/documentation/activitykit/activity) 和 [WidgetKit ActivityConfiguration](https://developer.apple.com/documentation/widgetkit/activityconfiguration) 从 macOS 27.3 起可用。
- [Bring Live Activities to Mac](https://developer.apple.com/videos/play/tech-talks/111467/) 介绍系统展示及交互。
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) 介绍更新、生命周期和载荷限制。
- [SwiftUI Link](https://developer.apple.com/documentation/swiftui/link) 提供系统活动行链接；后台转交使用内嵌 URL 辅助 App 与 `NSWorkspace.OpenConfiguration.activates = false`。
- [App Intent 主进程执行目标](https://developer.apple.com/documentation/appintents/intentexecutiontargets/main)用于共用动作定义；元数据存在不等于系统扩展分发成功，详见 [后台跳转](BACKGROUND-HANDOFF.md)。

## herdr

[herdr Socket API](https://herdr.dev/docs/socket-api/) 提供快照与 agent 聚焦。应用使用显式 `--session <name> api snapshot` 获取权威快照，通过 `agent attach <target>` 打开独立视图；公共 focus 方法会广播到多个客户端，应用导航不使用它。支持类型和集成方式以 [herdr Agents](https://herdr.dev/docs/agents/) 与 [Integrations](https://herdr.dev/docs/integrations/) 为准。

## 其他参考项目

项目设计过程中参考了 [shepherd](https://github.com/cryks/shepherd)、[herdr-agent-island](https://github.com/eliebak/herdr-agent-island)、[herdr-remote](https://github.com/dcolinmorgan/herdr-remote) 和 [LiveActivityDynamicIslandKit](https://github.com/mikonyaa/LiveActivityDynamicIslandKit)。它们的目标平台与实现方式不同，不能单独证明 macOS 实时活动能力。本项目未引入这些项目作为运行时依赖。
