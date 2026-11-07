# CI、原生 Release 与检查更新

`Checks` 在主分支提交、PR 和手动触发时运行 Swift 测试、桌面 Hook 测试、本地化检查、Xcode 项目生成一致性、Shell 语法检查及 Companion 构建。测试无需真实 herdr 服务或桌面客户端。Dependabot 每周检查 GitHub Actions 依赖版本。

## 发布

推送稳定版本标签 `vMAJOR.MINOR.PATCH` 触发 `Native Release`。工作流确认标签属于 main 历史，运行检查，构建 arm64 原生 App 和嵌入 Widget，统一两者版本及 build number，验证签名和包结构，生成 ZIP 与 SHA-256 文件后发布 GitHub Release。已发布的 Release 不会被重跑覆盖。

```bash
git tag v0.1.0
git push origin v0.1.0
```

手动运行 `Native Release` 时指定已有标签；默认只构建 Actions artifacts。勾选 `publish` 才会发布该手动运行。标签触发会自动发布。原生包为 ad-hoc 签名，不执行公证；不需要 Apple Developer、签名证书或 Apple ID secrets。

工作流默认使用 GitHub 的 `xcode-27` arm64 runner。原生 SDK 必须达到 27.3；托管镜像尚未提供该 SDK 时，此工作流会明确失败且不会发布不完整 App。可通过仓库 Actions variable `NATIVE_RELEASE_RUNNER` 指定装有兼容 Xcode 的受信任 runner 标签；兼容 Xcode 应安装在 Applications 目录中供自动探测。托管镜像加入 SDK 后默认配置即可构建。不要将 Companion 当作原生发布包。

本地构建同样的归档：

```bash
APP_VERSION=0.1.0 APP_BUILD=1 bash scripts/package-release.sh
```

产物为 `dist/releases/DynamicAgents-0.1.0-arm64.zip` 和同名 `.sha256` 文件。`dist/` 不纳入源码提交。

## App 检查更新

App 菜单和连接设置均提供“检查更新”。自动检查默认开启，最多每 24 小时一次，失败时保持安静；可在设置中关闭。手动检查会显示结果。

App 请求公开的 GitHub latest-release API，忽略 draft、prerelease、无效版本号及缺少原生归档的 Release，按数字比较稳定版本。下载和发布页面必须属于本仓库的同一标签。检查结果只打开发布页面，不会自行安装或替换 App，也不上传会话内容。发布时使用约定文件名，新的 GitHub Release 即成为更新源，无需另行维护 appcast。

隔离 UI 验证实例通过进程参数关闭自动检查，仍不依赖网络。系统窗口切换、自动化授权和系统 Widget 点击需要本机实测，普通 CI 不代替这些检查。

托管镜像参考：[runner 列表](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[xcode-27 SDK 清单](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)。
