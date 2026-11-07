# 精确定位终端窗口与 herdr session

主窗口、菜单和后台 App Intent 共用按客户端定位的路径。App 保留 herdr 客户端 PID、TTY、所属 App 和 session，使用终端原生 Apple Events 查询窗口、标签和分屏。不会通过激活整个 App 来猜测目标窗口。

`ProcessInventory` 读取进程父子关系、当前用户 herdr 进程的 argv，以及仅两个环境提示：`HERDR_SESSION`、`HERDR_SOCKET_PATH`。其他环境变量不解码、不保存。显式 session 参数优先于继承环境；自定义 socket 必须与所选服务实际返回的 socket 一致。server、查询进程、远程前端不会被当作本地交互窗口。

同一 App 的多个客户端不会合并。自动模式只在候选唯一时选择；否则到连接设置的“herdr 窗口”中选择，选项包含 session 和 TTY。手动指定客户端窗口时，该选择优先于其他窗口已有的 agent 直连视图；只有同一窗口内的直连视图会复用。所选客户端关闭后原选择失效，不会自动转向另一个窗口。更换终端 App 时，设置会清除属于其他 App 的窗口选择；取消不写入偏好。自动模式下，已有且唯一的目标 agent 直连视图优先复用。发现每 15 秒刷新一次，点击前再次刷新。

## 为什么使用直连视图

herdr 0.9.5 公共 socket 上的 `agent.focus` / `pane.focus` 会调用 `focus_all_shell_clients_on_default_target`，改变该 session 下所有 shell 客户端的位置。本机进程列表也无法证明没有远程客户端，因此 App 的导航路径完全不调用这些公共 focus 方法。

首次打开 agent 时，以显式 `--session <name> agent attach <pane>` 创建独立直连视图。Ghostty 1.3+ 和 iTerm2 在选定窗口中新建标签；Apple Terminal 使用其原生 `do script` 创建独立窗口。再次点击会发现并复用对应的直连终端。既有 herdr 窗口的 workspace、tab 和 pane 不被广播切换。命令只进入新建视图，不向现有 shell 或 agent 输入文本。

终端需要允许 Dynamic Agents 的“自动化”请求；拒绝时显示错误。其他终端暂不支持精确窗口操作，会明确报错。桌面 Hook 的终端宿主通过报告中的祖先 PID、实际 TTY、进程启动时间和宿主关系定位；已结束的窗口不会被其他窗口替代。一般桌面编辑器仍只激活报告中的宿主 App，不保证选中某个具体对话。

活动 ID 包含 session 的哈希命名空间，保留独立的原始 pane ID。不同 session 中同名的 pane 不共享活动 ID；设置切换后旧活动动作不会落到新 session。默认会话的所有 herdr 调用也显式使用 `--session default`，避免进程环境改变连接。

## 验证

```bash
HERDR_LIVE_TEST=1 swift test --build-system native
bash scripts/build-app.sh native
```

核心测试覆盖同 App 多客户端、命名 session、继承 socket、TTY 唯一匹配、直连复用策略和跨 session 活动隔离。实机需另行验证两个终端窗口、同 session 多客户端及不同命名 session：记录原窗口选择，点击 agent，确认只激活或新增目标视图，其他视图保持原位。

`scripts/verify-terminal.sh` 会实际打开或复用 agent 直连视图；它不向 agent 发送输入。报告中的全局 `focused_pane_id` 保持原值只是隔离证据，不能单独证明正确窗口被激活。后台 `perform()` 验证也不能代替系统 Widget 的实际鼠标点击。

参考：[Ghostty AppleScript](https://ghostty.org/docs/features/applescript)、[iTerm2 scripting dictionary](https://github.com/gnachman/iTerm2/blob/master/iTerm2.sdef)、herdr 0.9.5 `src/server/headless/client_views.rs`。
