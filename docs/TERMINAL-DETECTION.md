# 精确定位终端窗口与 herdr session

主窗口、菜单和系统实时活动共用按客户端定位的路径。App 保留 herdr 客户端 PID、TTY、启动时间、所属 App、session 和配置文件位置，使用终端原生 Apple Events 查询窗口、标签和分屏。

`ProcessInventory` 仅对当前用户的 herdr 进程读取 argv 和所需环境提示：`HERDR_SESSION`、`HERDR_SOCKET_PATH`、`HERDR_CONFIG_PATH`、`XDG_CONFIG_HOME`。其他环境变量不保存。显式 session 参数优先；继承的自定义 socket 必须匹配所选服务。server、查询进程和远程前端不会被当作本地交互窗口。

同一 App 的多个客户端保持独立。自动模式优先选择唯一的普通 herdr 客户端；没有普通客户端时，可使用唯一且已直连目标 agent 的页面。手动选择始终优先。多个候选需要在设置中指定“herdr 窗口”；所选客户端关闭后原选择失效。更换终端 App 会清除不兼容的窗口选择，取消不写入偏好。点击前重新发现客户端。

## 复用已有页面

Ghostty 1.3+、iTerm2 和 Apple Terminal 使用同一策略：按 TTY 唯一匹配已有终端 surface，读取目标客户端当前可见的 herdr 常规侧栏，结合服务端工作区、标签页和 Agent 元数据，唯一匹配目标条目并直接点击。正常跳转不打开 Go to 选择页，不按名称猜选另一个客户端。开始时通过该客户端自己的 pane-cycle 快捷键建立焦点上下文；App 读取客户端配置中的 `keys.prefix` 和 `keys.cycle_pane_next`，不会改写配置。

跳转及重复点击均不创建终端窗口、标签或 agent 直连进程。已直连另一个 agent 的页面不能作为普通 herdr 客户端使用，会返回错误并要求选择 herdr 窗口。常规侧栏须可用，并保持 herdr 的鼠标捕获开启；滚动可见列表后仍无法唯一确认条目、同一标签页内存在完全相同的 Agent 标识或使用无法识别的自定义布局时，返回说明，不退回选择页面。

herdr 0.9.5 公共 socket 的 `agent.focus` / `pane.focus` 会调用 `focus_all_shell_clients_on_default_target`，改变该 session 下所有 shell 客户端的位置。App 使用限定到已选 native surface 的本地输入，让 herdr 通过该客户端自己的 endpoint 选择页面。App 不调用会话范围的公共 focus，也不向 agent 输入请求文本。

终端需要允许 Dynamic Agents 的“自动化”请求；在普通 herdr 客户端内选择页面还需要 App 的“辅助功能”授权。App 只读取目标终端的可见文本和终端网格尺寸，并在锁屏、PID／启动时间变化、目标 surface 或前台 App 改变、侧栏无法识别、结果不唯一时停止。点击前进行新鲜的 native 命中检查；只接受属于所选终端 App 的目标。支持字符串及双引号单行数组的快捷键配置；无法解析的自定义格式会返回错误。

AppleScript 的字段分隔符在进入终端应用上下文前显式设为字符 9。`tab` 在终端脚本字典内可能表示“标签页”类型，不能用来拼接窗口列表的制表符。

桌面 Hook 的终端宿主继续通过报告中的祖先 PID、TTY、进程启动时间和宿主关系定位已有页面。一般桌面编辑器激活已观察到的宿主 App，暂不保证选中某个具体对话。

活动 ID 带有 session 哈希命名空间，原始 pane ID 单独保留。设置切换后，旧活动不会选择新 session 中同名的 pane。所有 herdr 调用显式传递 session，包括 `default`。

## 验证

核心测试覆盖同 App 多客户端、命名 session、继承端点及配置、TTY 唯一匹配、已有页面选择策略、侧栏匹配、截断与重复标签。原生验证还记录 `exactWindowVerified` 与 `terminalViewsUnchanged`。全局 `focused_pane_id` 不变只是隔离证据。诊断用的 `currentPane` 仍可打开 Go to 来独立读取客户端页面；应在计时和观察正常动作之外执行，不能把诊断选择页当作产品跳转路径。

实机分别验证 Ghostty、iTerm2 和 Apple Terminal：建立一次性 session 和两个客户端，记录每个客户端的当前页面及 surface。选择目标客户端内另一页面，再重复点击；要求目标页面正确、终端 surface 集合不变、其他客户端页面不变。分别覆盖主窗口、菜单和系统活动行。系统活动还需检查主 App 激活次数；直接调用动作不能代替系统控件测试。

参考：[Ghostty AppleScript](https://ghostty.org/docs/features/applescript)、[iTerm2 scripting dictionary](https://github.com/gnachman/iTerm2/blob/master/iTerm2.sdef)、herdr 0.9.5 `src/client/shell/aggregate_navigation.rs`、`src/client/shell/overlay_input.rs` 和 `src/server/headless/client_views.rs`。
