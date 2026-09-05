import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var globalHotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private var state: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let arguments = Set(CommandLine.arguments)
        let recordStore = makeRecordStore(demo: arguments.contains("--demo") || arguments.contains("--diff-demo"))
        let clipboardStore = makeClipboardStore(demo: arguments.contains("--clipboard-demo") || arguments.contains("--diff-demo"))
        let state = AppState(recordStore: recordStore, clipboardStore: clipboardStore)
        self.state = state
        let panelController = PanelController(state: state)
        self.panelController = panelController

        configureStatusItem()

        do {
            globalHotKey = try GlobalHotKey { [weak panelController] in
                panelController?.toggle()
            }
        } catch {
            panelController.showWithoutSource(message: error.localizedDescription)
        }

        requestRequiredPermissionsAtLaunch(arguments: arguments, clipboardStore: clipboardStore)

        if arguments.contains("--json-demo") {
            state.jsonInput = #"{"service":"gateway","ports":[80,443],"enabled":true}"#
            state.switchMode(.json)
        }
        if arguments.contains("--json-error-demo") {
            state.jsonInput = """
            {
              "service": "gateway",
              "ports": [80, 443,],
              "enabled": true
            }
            """
            state.switchMode(.json)
        }
        if arguments.contains("--clipboard-demo") {
            state.switchMode(.clipboard)
        }
        if arguments.contains("--diff-demo") {
            state.textDiff.leftText = """
            # Luma 服务配置
            service: gateway
            version: 1.0.0
            host: localhost
            port: 8080

            # 访问控制
            auth: enabled
            timeout: 30
            retries: 3

            # 发布说明
            欢迎使用 Luma ✨
            支持预设文本与 JSON
            """
            state.textDiff.rightText = """
            # Luma 服务配置
            service: gateway
            version: 1.1.0
            host: localhost
            port: 9090

            # 访问控制
            auth: enabled
            timeout: 60
            retries: 3
            cache: true

            # 发布说明
            欢迎使用 Luma ✨
            支持预设文本、JSON 与文本 Diff
            """
            state.switchMode(.diff)
        }
        let hasPresentationArgument = arguments.contains("--show")
            || arguments.contains("--demo")
            || arguments.contains("--clipboard-demo")
            || arguments.contains("--json-demo")
            || arguments.contains("--json-error-demo")
            || arguments.contains("--diff-demo")
        if hasPresentationArgument {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if arguments.contains("--diff-demo") {
                    panelController.showWithoutSource()
                } else {
                    panelController.show()
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                panelController.showWithoutSource()
            }
        }
        if let snapshotPath = value(after: "--snapshot", in: CommandLine.arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                do {
                    try panelController.saveSnapshot(to: URL(fileURLWithPath: snapshotPath))
                } catch {
                    NSLog("Luma 截图失败：%@", error.localizedDescription)
                }
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            panelController?.showWithoutSource()
        }
        return true
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            panelController?.toggle()
            return
        }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            panelController?.toggle()
        }
    }

    @objc private func showPanel() {
        panelController?.show()
    }

    @objc private func newRecord() {
        panelController?.show()
        panelController?.state.beginNewRecord()
    }

    @objc private func showJSON() {
        panelController?.show()
        panelController?.state.switchMode(.json)
    }

    @objc private func showClipboard() {
        panelController?.show()
        panelController?.state.switchMode(.clipboard)
    }

    @objc private func showDiff() {
        panelController?.show()
        panelController?.state.switchMode(.diff)
    }

    @objc private func checkForUpdates() {
        panelController?.showWithoutSource(message: "正在检查 GitHub Release…")
        state?.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func requestRequiredPermissionsAtLaunch(
        arguments: Set<String>,
        clipboardStore: ClipboardHistoryStore
    ) {
        let isAutomatedRun = arguments.contains("--snapshot")
            || arguments.contains("--demo")
            || arguments.contains("--clipboard-demo")
            || arguments.contains("--json-demo")
            || arguments.contains("--json-error-demo")
            || arguments.contains("--diff-demo")
        guard !isAutomatedRun else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            clipboardStore.requestReadAccess()
            _ = SendTextEngine.isAccessibilityTrusted(prompt: true)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "command", accessibilityDescription: "Luma")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = "Luma"
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.toolTip = "Luma · 左键打开，右键显示菜单"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        DispatchQueue.main.async {
            item.isVisible = true
            NSLog(
                "Luma 菜单栏项目：visible=%@, length=%.1f, buttonWindow=%@",
                item.isVisible ? "true" : "false",
                item.length,
                String(describing: item.button?.window)
            )
        }
    }

    private func showStatusMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Luma", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "新建记录", action: #selector(newRecord), keyEquivalent: "n")
        menu.addItem(withTitle: "剪贴板历史", action: #selector(showClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "JSON 工具", action: #selector(showJSON), keyEquivalent: "j")
        menu.addItem(withTitle: "文本 Diff", action: #selector(showDiff), keyEquivalent: "4")
        menu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Luma", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Luma")
        appMenu.addItem(
            withTitle: "关于 Luma",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Luma", action: #selector(quit), keyEquivalent: "q")
        for item in appMenu.items where item.action == #selector(checkForUpdates) || item.action == #selector(quit) {
            item.target = self
        }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func makeRecordStore(demo: Bool) -> RecordStore {
        guard demo else { return RecordStore() }

        let demoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-preview-\(ProcessInfo.processInfo.processIdentifier).json")
        let store = RecordStore(fileURL: demoURL)

        var greeting = RecordDraft()
        greeting.name = "问候语"
        greeting.text = "你好，欢迎使用 Luma。"
        greeting.aliasesText = "hello"
        greeting.tagsText = "示例"
        greeting.isFavorite = true

        var hidden = RecordDraft()
        hidden.name = "隐藏预览示例"
        hidden.text = "这段示例文本不会显示在搜索结果中。"
        hidden.tagsText = "示例"
        hidden.hidePreview = true

        var reply = RecordDraft()
        reply.name = "常用回复"
        reply.text = "收到，我确认后回复你。"
        reply.aliasesText = "reply"
        reply.tagsText = "chat"

        try? store.save(greeting)
        try? store.save(hidden)
        try? store.save(reply)
        return store
    }

    private func makeClipboardStore(demo: Bool) -> ClipboardHistoryStore {
        guard demo else { return ClipboardHistoryStore() }

        let demoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-clipboard-preview-\(ProcessInfo.processInfo.processIdentifier).json")
        let store = ClipboardHistoryStore(fileURL: demoURL, startMonitoring: false)
        store.record(
            text: "https://example.com/docs",
            sourceAppName: "Safari",
            sourceBundleIdentifier: "com.apple.Safari",
            copiedAt: Date().addingTimeInterval(-420)
        )
        store.record(
            text: "收到，我稍后确认完整信息后回复你。",
            sourceAppName: "信息",
            sourceBundleIdentifier: "com.apple.MobileSMS",
            copiedAt: Date().addingTimeInterval(-95)
        )
        store.record(
            text: "git status --short",
            sourceAppName: "终端",
            sourceBundleIdentifier: "com.apple.Terminal",
            copiedAt: Date().addingTimeInterval(-18)
        )
        return store
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
