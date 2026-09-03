# Luma

Luma 是一个原生 macOS 全局 Send Text 面板，并包含 JSON 格式化、高亮和精确错误定位。

## 当前功能

- `⌥ Space` 从任意应用呼出。
- 使用名称、别名或标签搜索统一的文本记录。
- 将记录原文发送到呼出前聚焦的位置。
- 可选解析 `\n`、`\r`、`\t`、`\e`、`\a` 和 `\\`。
- 可选隐藏正文预览。
- 可将正文存入 macOS Keychain，避免写入记录数据库。
- 可限制记录允许发送到哪些 bundle identifier。
- JSON 严格校验、2/4 空格格式化、压缩、语义高亮、中文错误与行列定位。

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

当前自动构建使用 ad-hoc 签名，适合开发测试。正式分发时应在仓库 Secrets 中配置 Developer ID，并增加 Apple notarization 步骤。

## 权限

浏览和 JSON 功能不需要额外权限。第一次向其他应用发送文本时，macOS 会要求辅助功能权限：

`系统设置 → 隐私与安全性 → 辅助功能 → Luma`

授权后重新触发发送即可。

## 数据位置

- 普通记录：`~/Library/Application Support/Luma/records.json`
- 开启“存入钥匙串”的正文：macOS Keychain，service 为 `com.luma.app.records`

用户创建的记录与钥匙串内容仅保存在本机，不属于源码仓库，也不会被构建脚本复制进应用包。

## 仓库隐私

- 不提交用户记录、日志、构建缓存、预览文件或打包产物。
- 不提交环境变量文件、签名证书、配置描述文件或其他凭据文件。
- Git 提交使用项目级中性身份，不依赖开发者的全局姓名或私人邮箱。

## 当前开发约束

- 默认快捷键暂时固定为 `⌥ Space`。
- 跨应用输入依赖目标应用对 Accessibility 或 CGEvent 的支持，需要继续覆盖终端 Secure Input 等真实场景。
- 当前 `.app` 使用 ad-hoc 签名，仅供本机开发测试；正式分发需要 Developer ID 签名与 notarization。
