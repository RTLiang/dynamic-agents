# 终端自动识别

聚焦 agent 时，App 先调用 herdr 聚焦 pane，再激活宿主终端。主窗口、菜单栏和后台 App Intent 共用该流程。

`ProcessInventory` 使用系统进程表获取父子关系，并读取当前用户 herdr 进程的可执行路径和 argv；不读取环境变量。`TerminalResolver` 匹配交互式本地会话并沿父进程链寻找宿主 App，排除后台 server、查询进程和远程客户端。默认会话、`--session name` 和 `session attach name` 均可识别。

检测结果分为找到一个、找到多个和未找到。自动模式只激活有进程关系证据的终端；多个候选时可在设置中选择。检测每 15 秒刷新一次，打开设置或执行终端操作前也会刷新。只修改终端偏好不会结束实时活动。

同一终端 App 的多个窗口尚未精确区分；不需要辅助功能或 Apple Events 权限来执行实际终端激活。

```bash
HERDR_LIVE_TEST=1 swift test --build-system native
bash scripts/build-app.sh companion
bash scripts/verify-terminal.sh
```

验证脚本需要本机 herdr 会话和连接中的终端；只重新聚焦当前 pane，不向 agent 发送输入。本机生成的报告不会纳入公开仓库。
