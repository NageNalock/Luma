import Foundation

enum CommandLaunchSelfTests {
    @MainActor
    static func run(check: (String, Bool) -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-launch-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func rejected(_ kind: RecordKind, _ content: String) -> Bool {
            do { _ = try CommandLaunchPlan(kind: kind, content: content); return false }
            catch { return true }
        }

        func execute(_ plan: CommandLaunchPlan) throws -> (Int32, URL) {
            let wrapper = try plan.writeTerminalScript()
            defer { try? FileManager.default.removeItem(at: wrapper.deletingLastPathComponent()) }
            let attributes = try FileManager.default.attributesOfItem(atPath: wrapper.path)
            check("launch wrapper is private and executable", (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            let process = Process()
            process.executableURL = wrapper
            var environment = ProcessInfo.processInfo.environment
            // Do not run the user's shell startup files during tests.
            environment["ZDOTDIR"] = directory.path
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            check("launch wrapper cleans itself up", !FileManager.default.fileExists(atPath: wrapper.deletingLastPathComponent().path))
            return (process.terminationStatus, wrapper)
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "cd /\n".write(to: directory.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
            let script = directory.appendingPathComponent("启动 Qwen's $(unused).command")
            let output = directory.appendingPathComponent("output.txt")
            let payload = "#!/bin/sh\nprintf '%s' \"$PWD\" > \(CommandLaunchPlan.shellQuote(output.path))\n"
            try payload.write(to: script, atomically: true, encoding: .utf8)
            check("reject non-executable script", rejected(.script, script.path))
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

            let plan = try CommandLaunchPlan(kind: .script, content: script.path)
            let result = try execute(plan)
            let actualDirectory = try String(contentsOf: output, encoding: .utf8)
            check("launch script with Unicode, spaces, quotes and shell metacharacters", result.0 == 0)
            check("script runs from its own directory after login profile", URL(fileURLWithPath: actualDirectory).resolvingSymlinksInPath() == directory.resolvingSymlinksInPath())

            let literal = "中文 ' quote $HOME `literal` \\n\n第二行"
            let command = "value=\(CommandLaunchPlan.shellQuote(literal))\nprintf '%s' \"$value\" > \(CommandLaunchPlan.shellQuote(output.path))"
            let commandResult = try execute(CommandLaunchPlan(kind: .command, content: command))
            let actualText = try String(contentsOf: output, encoding: .utf8)
            check("multiline command preserves literal text and escapes", commandResult.0 == 0 && actualText == literal)
            let failureResult = try execute(CommandLaunchPlan(kind: .command, content: "exit 7"))
            check("command exit status propagates to Terminal", failureResult.0 == 7)

            check("reject missing script", rejected(.script, directory.appendingPathComponent("missing.command").path))
            check("reject directory as script", rejected(.script, directory.path))
            check("reject relative script path", rejected(.script, "test.command"))
            check("reject blank command", rejected(.command, " \n\t"))
            check("reject null byte", rejected(.command, "echo\0test"))
            check("never execute text records", rejected(.text, "echo test"))

            let legacy = TextRecord(name: "旧文本", text: "echo do-not-run")
            let launcher = TextRecord(name: "启动测试", text: command, kind: .command, aliases: ["launch"])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var objects = try JSONSerialization.jsonObject(with: encoder.encode([legacy, launcher])) as! [[String: Any]]
            objects[0].removeValue(forKey: "kind")
            let recordsURL = directory.appendingPathComponent("records.json")
            try JSONSerialization.data(withJSONObject: objects).write(to: recordsURL)
            let store = RecordStore(fileURL: recordsURL)
            check("legacy library loads alongside launchers", store.records.count == 2 && store.records.first?.kind == .text)
            check("launcher aliases remain searchable", RecordSearch.results(for: "launch", in: store.records).first?.id == launcher.id)
            let clipboardStore = ClipboardHistoryStore(fileURL: directory.appendingPathComponent("clipboard.json"), startMonitoring: false)
            let state = AppState(recordStore: store, clipboardStore: clipboardStore)
            var sentText: String?
            var launchedCommand: String?
            state.onSendText = { text, _ in sentText = text }
            state.onLaunchCommand = { text, _ in launchedCommand = text }
            state.selectedRecordID = legacy.id
            state.performPrimaryAction()
            check("legacy text routes only to text action", sentText == legacy.text && launchedCommand == nil)
            sentText = nil
            state.selectedRecordID = launcher.id
            state.performPrimaryAction()
            check("launcher routes without pasting or requiring a source app", launchedCommand == command && sentText == nil)
            launchedCommand = nil
            state.isLaunchingCommand = true
            state.performPrimaryAction()
            check("duplicate launch suppressed while opening Terminal", launchedCommand == nil)

            var draft = RecordDraft(record: launcher, resolvedText: command)
            draft.name = "已编辑启动项"
            draft.interpretEscapes = true
            draft.allowedAppsText = "com.example.target"
            try store.save(draft)
            let saved = RecordStore(fileURL: recordsURL).records.first { $0.id == launcher.id }
            check("editing persists launch kind and exact command", saved?.kind == .command && saved?.text == command)
            check("text-only options do not affect launchers", saved?.interpretEscapes == false && saved?.allowedBundleIdentifiers.isEmpty == true)
        } catch {
            check("launcher tests: \(error.localizedDescription)", false)
        }
    }
}
