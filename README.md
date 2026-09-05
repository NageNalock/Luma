# Luma

Luma 是一个原生 macOS 全局 Send Text 面板，并包含 JSON 格式化、高亮和精确错误定位。

## 当前功能

- `⌥ Space` 从任意应用呼出。
- 使用名称、别名或标签搜索统一的文本记录。
- 将记录原文发送到呼出前聚焦的位置。
- 自动记录 Luma 运行期间新复制的文本，支持搜索最近 200 条剪贴板历史。
- 从历史中选择内容后，先恢复剪贴板，再自动向呼出前的应用发送 `⌘V`；也可只恢复后手动粘贴。
- 可选解析 `\n`、`\r`、`\t`、`\e`、`\a` 和 `\\`。
- 可选隐藏正文预览。
- 可将正文存入 macOS Keychain，避免写入记录数据库。
- 可限制记录允许发送到哪些 bundle identifier。
- JSON 严格校验、2/4 空格格式化、压缩、语义高亮、中文错误与行列定位。
- 主界面、菜单栏和应用菜单均可检查 GitHub Release 更新或彻底退出进程。
- Dock 与菜单栏都会显示 Luma；点击 Dock 图标可重新打开主面板。

## 更新

点击主界面右下角的“更新”，Luma 会读取 `NageNalock/Luma` 的 GitHub Releases。当前自动发布产出的是 prerelease，因此稳定版与预发布版都会参与版本比较。

发现新版本后，Luma 会把 DMG 下载到自身缓存目录，使用 Release 同名 `.sha256` 文件校验内容，再自动打开 DMG。安装仍由用户将新版本拖入“应用程序”完成；Luma 不会自行覆盖应用，也不需要访问“下载”文件夹。

## 构建

当前工程可以直接使用 macOS Command Line Tools：

```bash
swift build
swift run Luma --self-test
```

生成可运行的 `.app`：

```bash
chmod +x scripts/package-app.sh
./scripts/package-app.sh
open ../outputs/Luma.app
```

也可以在安装完整 Xcode 后直接打开 `Package.swift`。

## 自动发布

每次推送到 `main` 分支后，GitHub Actions 会运行自测、交叉编译 arm64 与 x86_64、合并为 Universal 2 应用，并创建包含 DMG 与 SHA-256 校验文件的 prerelease。也可以在 Actions 页面手动触发同一流程。

当前自动构建使用 ad-hoc 签名，适合开发测试。正式分发时应在仓库 Secrets 中配置 Developer ID，并增加 Apple notarization 步骤。更新器不会改变签名状态；ad-hoc 构建替换应用后，macOS 仍可能要求重新确认既有隐私权限。

## 权限

浏览记录和 JSON 功能不需要额外权限。第一次向其他应用发送预设文本或自动粘贴剪贴板历史时，macOS 会要求辅助功能权限：

`系统设置 → 隐私与安全性 → 辅助功能 → Luma`

授权后重新触发发送即可。

剪贴板历史通过 macOS 系统剪贴板读取文本。较新的 macOS 版本可能首次询问是否允许 Luma 读取剪贴板；选择“始终允许”后即可持续记录。即使没有辅助功能权限，Luma 仍能把选中的历史内容放回剪贴板，之后可手动按 `⌘V`。

## 数据位置

- 普通记录：`~/Library/Application Support/Luma/records.json`
- 文本剪贴板历史：`~/Library/Application Support/Luma/clipboard-history.json`
- 开启“存入钥匙串”的正文：macOS Keychain，service 为 `com.luma.app.records`

用户创建的记录、剪贴板历史与钥匙串内容仅保存在本机，不属于源码仓库，也不会被构建脚本复制进应用包。剪贴板历史仅记录文本、自动去重并限制为最近 200 条；清空操作不可撤销。

## 仓库隐私

- 不提交用户记录、日志、构建缓存、预览文件或打包产物。
- 不提交环境变量文件、签名证书、配置描述文件或其他凭据文件。
- Git 提交使用项目级中性身份，不依赖开发者的全局姓名或私人邮箱。

## 当前开发约束

- 默认快捷键暂时固定为 `⌥ Space`。
- 跨应用输入依赖目标应用对 Accessibility 或 CGEvent 的支持，需要继续覆盖终端 Secure Input 等真实场景。
- 当前 `.app` 使用 ad-hoc 签名，仅供本机开发测试；正式分发需要 Developer ID 签名与 notarization。
