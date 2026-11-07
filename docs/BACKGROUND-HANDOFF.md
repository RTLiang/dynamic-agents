# 后台终端跳转

原生包只包含主 App 和 `Contents/PlugIns/DynamicAgentsWidgets.appex`。主 App 持有 ActivityKit 活动并负责监控；系统 Widget 扩展处理活动行的点击。没有额外的后台宿主 App，也没有为活动创建临时 Dock 项或切换应用类型的代码。

## 点击路径

会话行使用 `Button(intent:)`。`FocusAgentIntent` 仅编入 Widget，声明 `supportedModes = .background` 和 `allowedExecutionTargets = .widgetKitExtension`。点击先在系统管理的 Widget 进程执行，再向主 App 转交有界的会话 ID。Widget 本身仍是 macOS 的扩展进程；它不创建应用窗口或 Dock 项。

主 App 未运行时，Widget 使用公开的 `NSWorkspace.OpenConfiguration`，以 `activates = false`、`hides = true` 启动其所属 App。主 App 的接收器和监控在 AppDelegate 启动阶段建立，不依赖主窗口出现。只有明确点击仪表盘链接才以前台方式打开主窗口。

转交使用请求 UUID、重试和回执。沙盒中的 Widget 以分布式通知的 `object` 字符串携带有界编码，`userInfo` 保持为空。主 App 检查 UUID、载荷长度与会话 ID，去除重复请求，再调用共用的 `AgentFocusAction`。动作重新读取当前状态，拒绝已结束或其他 session 的 ID，并使用选定客户端的已有页面。请求重试不重复执行；错误通过 App Intent 返回，不启动辅助 App 显示警告框。

## 执行目标与签名

本机 macOS 27.3 的隔离样例中，`.main` 执行目标未进入 `perform()`，而相同 ad-hoc 签名下的 `.widgetKitExtension` 目标成功响应了真实系统点击，并在主 App 未运行时完成后台启动与回执。该结果说明不能把 `Unable to get teamId`、`requiresValidatedBundle` 日志概括为“ad-hoc 不支持 Widget App Intent”；这些日志也可能来自快捷指令注册连接。

当前路径明确选择 Widget 内后台执行，保留默认 ad-hoc 构建，不依赖额外证书或辅助宿主来绕行。

## 生命周期与安装

主 App 直接创建、更新和结束活动。没有符合条件的 agent 时隐藏活动，监控继续；出现符合条件的会话后恢复。用户或系统结束活动会停用活动开关，重新启用后才创建。退出主 App 时等待 ActivityKit 结束；关闭主窗口或隐藏菜单栏图标不会退出监控。

安装器注销旧注册，停止身份及启动时间均已核对的 Widget 或旧版辅助进程，再将旧安装移到废纸篓。新包只注册主 App 与其 Widget。旧宿主的清理逻辑保留用于升级，发布校验会拒绝仍含辅助 App 的包。不会重置系统 Launch Services 或终止系统 Widget 渲染进程。

自动化和辅助功能授权属于实际执行定位的主 App。开发中的 ad-hoc 重签名可能使已开启的辅助功能记录失效；仅切换开关不一定更新旧签名记录。经过用户授权时，可在系统设置中移除该 App 的旧条目，再重新加入当前安装包。系统若要求密码或 Touch ID，必须由用户完成；App 和验证工具不读取或代填凭据。

## 验证

`--verify-live-activity` 直接检查 ActivityKit 的启动、内容更新、结束、空列表隐藏和后台恢复。后台定位报告调用共用动作，不等于系统点击测试。

系统路径单独测试：对真实可见活动行进行新鲜命中检查后点击，要求 Widget 开始执行、主 App 完成动作、Widget 收到回执；核对目标页面、surface、视图数量和主 App 激活次数。分别覆盖运行中、重复点击和主 App 未运行。还应检查没有旧辅助 App 进程、额外 Dock 项或主窗口闪现。无障碍动作与实际鼠标点击分别记录。

证据保存在忽略的 `.build/`。herdr 页面隔离、终端支持及限制见 [终端定位](TERMINAL-DETECTION.md)。
