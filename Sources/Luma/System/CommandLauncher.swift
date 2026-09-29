import AppKit

enum CommandLaunchError: LocalizedError {
    case emptyCommand
    case invalidContent
    case invalidScriptPath
    case scriptNotFound
    case scriptNotExecutable
    case notALauncher
    case terminalUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyCommand: return "请输入要运行的命令。"
        case .invalidContent: return "命令或路径不能包含空字符。"
        case .invalidScriptPath: return "请选择脚本文件，或输入以 / 或 ~/ 开头的完整路径。"
        case .scriptNotFound: return "找不到脚本文件，请检查路径。"
        case .scriptNotExecutable: return "脚本没有执行权限，请先为该文件添加执行权限。"
        case .notALauncher: return "文本记录不能作为命令运行。"
        case .terminalUnavailable: return "找不到 macOS 终端应用。"
        }
    }
}

struct CommandLaunchPlan {
    let workingDirectory: URL
    let command: String

    init(kind: RecordKind, content: String) throws {
        guard !content.contains("\0") else { throw CommandLaunchError.invalidContent }
        switch kind {
        case .text:
            throw CommandLaunchError.notALauncher
        case .script:
            let path = (content.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
            guard path.hasPrefix("/") else { throw CommandLaunchError.invalidScriptPath }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw CommandLaunchError.scriptNotFound
            }
            guard FileManager.default.isExecutableFile(atPath: path) else {
                throw CommandLaunchError.scriptNotExecutable
            }
            let scriptURL = URL(fileURLWithPath: path)
            workingDirectory = scriptURL.deletingLastPathComponent()
            command = "exec " + Self.shellQuote(scriptURL.path)
        case .command:
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CommandLaunchError.emptyCommand
            }
            workingDirectory = FileManager.default.homeDirectoryForCurrentUser
            // Preserve all shell syntax, including quotes, backslashes and multiple lines.
            command = content
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    func writeTerminalScript() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("Luma.command")
        do {
            // Delete the private wrapper before running; the selected user script is never modified.
            let invocation = "cd -- \(Self.shellQuote(workingDirectory.path)) || exit 1\n" + command
            let script = """
            #!/bin/zsh
            /bin/rm -f -- "$0"
            /bin/rmdir -- \(Self.shellQuote(directory.path))
            exec /bin/zsh -l -c \(Self.shellQuote(invocation))

            """
            try Data(script.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

@MainActor
enum CommandLauncher {
    static func launch(kind: RecordKind, content: String) async throws {
        let plan = try CommandLaunchPlan(kind: kind, content: content)
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw CommandLaunchError.terminalUnavailable
        }
        let script = try plan.writeTerminalScript()
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: configuration)
        } catch {
            try? FileManager.default.removeItem(at: script.deletingLastPathComponent())
            throw error
        }
    }
}
