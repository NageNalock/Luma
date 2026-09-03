import Foundation

enum SelfTestRunner {
    private struct Failure {
        let name: String
        let detail: String
    }

    @MainActor
    static func run() -> Bool {
        var failures: [Failure] = []
        var checksRun = 0

        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            checksRun += 1
            if !condition() {
                failures.append(Failure(name: name, detail: "condition was false"))
            }
        }

        check("valid JSON object", JSONDiagnosticParser.validate(#"{"name":"Luma","port":22,"active":true,"value":null}"#) == nil)
        check("valid top-level value", JSONDiagnosticParser.validate(#""top-level string""#) == nil)
        check("reject trailing comma", JSONDiagnosticParser.validate(#"{"a":1,}"#)?.message == "JSON 不允许对象末尾逗号")
        check("reject invalid escape", JSONDiagnosticParser.validate(#"{"a":"\q"}"#)?.message == "无效的字符串转义")
        check("reject leading zero", JSONDiagnosticParser.validate(#"{"a":01}"#)?.message == "数字不能包含前导零")

        let missingComma = JSONDiagnosticParser.validate("""
        {
          "名称": "服务"
          "port": 22
        }
        """)
        check("diagnostic line", missingComma?.line == 3)
        check("diagnostic column", missingComma?.column == 3)

        do {
            let pretty = try JSONTextFormatter.pretty(#"{"z":1.2300e+4,"a":{"empty":[],"text":"a b"}}"#)
            check("pretty preserves key order", pretty.range(of: #""z": 1.2300e+4"#) != nil)
            check("pretty preserves empty container", pretty.range(of: #""empty": []"#) != nil)

            let minified = try JSONTextFormatter.minified("""
            {
              "message": "keep  two spaces",
              "items": [1, 2]
            }
            """)
            check("minify preserves string whitespace", minified == #"{"message":"keep  two spaces","items":[1,2]}"#)
        } catch {
            failures.append(Failure(name: "formatter", detail: error.localizedDescription))
        }

        check(
            "escape sequence parsing",
            EscapeSequenceParser.parse(#"first\nsecond\t\e\\unknown\q"#) == "first\nsecond\t\u{1B}\\unknown\\q"
        )

        let records = [
            TextRecord(name: "问候语", text: "你好", aliases: ["hello"], tags: ["示例"]),
            TextRecord(name: "常用回复", text: "收到", aliases: ["reply"], tags: ["chat"])
        ]
        check("search alias", RecordSearch.results(for: "hello", in: records).first?.name == "问候语")
        check("search tag", RecordSearch.results(for: "chat", in: records).first?.name == "常用回复")

        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Luma-self-test-\(UUID().uuidString).json")
        let secureStore = MemorySecureTextStore()
        defer { try? FileManager.default.removeItem(at: persistenceURL) }

        do {
            let store = RecordStore(fileURL: persistenceURL, secureStore: secureStore)
            var draft = RecordDraft()
            draft.name = "受保护记录"
            draft.text = UUID().uuidString
            draft.isProtected = true
            try store.save(draft)

            let metadata = try String(contentsOf: persistenceURL, encoding: .utf8)
            let resolvedText = try store.resolvedText(for: store.records[0])
            check("protected text omitted from metadata", !metadata.contains(draft.text))
            check("protected text resolves from secure store", resolvedText == draft.text)
            check("protected preview is hidden", store.records[0].hidePreview && store.records[0].text == nil)
        } catch {
            failures.append(Failure(name: "record persistence", detail: error.localizedDescription))
        }

        if failures.isEmpty {
            print("Luma self-test: \(checksRun) checks passed")
            return true
        }

        print("Luma self-test failed:")
        for failure in failures {
            print("- \(failure.name): \(failure.detail)")
        }
        return false
    }

}

private final class MemorySecureTextStore: SecureTextStoring {
    private var values: [UUID: String] = [:]

    func set(_ text: String, for id: UUID) throws {
        values[id] = text
    }

    func text(for id: UUID) throws -> String {
        guard let value = values[id] else { throw MemorySecureTextStoreError.notFound }
        return value
    }

    func delete(for id: UUID) throws {
        values[id] = nil
    }
}

private enum MemorySecureTextStoreError: Error {
    case notFound
}
