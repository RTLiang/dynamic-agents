# 原生实时活动验证

原生目标需要 macOS 27.3 或更新版本与对应 SDK。构建脚本在未显式设置 `DEVELOPER_DIR` 时查找支持的 Xcode，不修改全局工具链。

## 安装和验证

```bash
bash scripts/install-app.sh
bash scripts/install-app.sh --verify-live-activity "$PWD/.build/live-activity-check.json"
```

安装脚本构建 App 和 Widget，退出旧实例，清理重复注册并注册安装目录内的扩展。替换前的安装包进入废纸篓。验证需要一个已连接的 herdr 终端，且至少有一个运行中的 agent。

验证分别检查 ActivityKit 授权、启动、更新、结束、空列表隐藏、后台恢复和终端跳转。Widget 渲染还需要检查系统日志，生命周期成功本身不能证明渲染成功：

```bash
/usr/bin/log show --last 5m --style compact \
  --predicate 'process == "chronod" AND eventMessage CONTAINS "dev.local.dynamicagents"' \
  > .build/widget-check.log
python3 scripts/check-widget-log.py .build/widget-check.log --activity-id <monitoringID>
```

日志检查只针对提供的活动和捕获时段；需要另行检查实际系统界面。后台 intent 的自动测试直接调用 `perform()`，不等同系统 Widget 的物理点击测试。
