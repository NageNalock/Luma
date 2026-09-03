import Foundation

struct JSONDiagnostic: Error, Equatable, Identifiable {
    let message: String
    let offset: Int
    let line: Int
    let column: Int
    let expected: String?

    var id: String { "\(offset)-\(message)" }

    var summary: String {
        "第 \(line) 行，第 \(column) 列：\(message)"
    }
}

enum JSONDiagnosticParser {
    static func validate(_ input: String) -> JSONDiagnostic? {
        var parser = Parser(bytes: Array(input.utf8))
        do {
            try parser.parseDocument()
            return nil
        } catch let issue as ParseIssue {
            let location = location(in: parser.bytes, at: issue.offset)
            return JSONDiagnostic(
                message: issue.message,
                offset: issue.offset,
                line: location.line,
                column: location.column,
                expected: issue.expected
            )
        } catch {
            let location = location(in: parser.bytes, at: parser.index)
            return JSONDiagnostic(
                message: "JSON 无法解析",
                offset: parser.index,
                line: location.line,
                column: location.column,
                expected: nil
            )
        }
    }

    private static func location(in bytes: [UInt8], at rawOffset: Int) -> (line: Int, column: Int) {
        let offset = min(max(0, rawOffset), bytes.count)
        var line = 1
        var column = 1
        var index = 0

        while index < offset {
            let byte = bytes[index]
            if byte == 0x0D {
                line += 1
                column = 1
                if index + 1 < offset, bytes[index + 1] == 0x0A {
                    index += 1
                }
            } else if byte == 0x0A {
                line += 1
                column = 1
            } else if byte & 0xC0 != 0x80 {
                column += 1
            }
            index += 1
        }
        return (line, column)
    }
}

private struct ParseIssue: Error {
    let message: String
    let offset: Int
    let expected: String?
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0
    private var depth = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseDocument() throws {
        skipWhitespace()
        guard index < bytes.count else {
            throw issue("请输入 JSON", expected: "JSON 值")
        }
        try parseValue()
        skipWhitespace()
        guard index == bytes.count else {
            throw issue("根值之后存在多余内容", expected: "文件末尾")
        }
    }

    private mutating func parseValue() throws {
        guard index < bytes.count else {
            throw issue("JSON 值不完整", expected: "对象、数组、字符串、数字、true、false 或 null")
        }

        switch bytes[index] {
        case 0x7B: try parseObject()       // {
        case 0x5B: try parseArray()        // [
        case 0x22: try parseString()       // "
        case 0x74: try parseLiteral("true")
        case 0x66: try parseLiteral("false")
        case 0x6E: try parseLiteral("null")
        case 0x2D, 0x30...0x39: try parseNumber()
        default:
            throw issue("无法识别的 JSON 值", expected: "对象、数组、字符串、数字、true、false 或 null")
        }
    }

    private mutating func parseObject() throws {
        try enterContainer()
        index += 1
        skipWhitespace()
        if consume(0x7D) { leaveContainer(); return }

        while true {
            guard peek == 0x22 else {
                throw issue("对象属性名必须使用双引号", expected: "属性名")
            }
            try parseString()
            skipWhitespace()
            guard consume(0x3A) else {
                throw issue("属性名后缺少冒号", expected: "':'")
            }
            skipWhitespace()
            try parseValue()
            skipWhitespace()

            if consume(0x7D) { leaveContainer(); return }
            guard consume(0x2C) else {
                throw issue("对象属性之间缺少逗号", expected: "',' 或 '}'")
            }
            skipWhitespace()
            if peek == 0x7D {
                throw issue("JSON 不允许对象末尾逗号", expected: "下一个属性名")
            }
        }
    }

    private mutating func parseArray() throws {
        try enterContainer()
        index += 1
        skipWhitespace()
        if consume(0x5D) { leaveContainer(); return }

        while true {
            try parseValue()
            skipWhitespace()
            if consume(0x5D) { leaveContainer(); return }
            guard consume(0x2C) else {
                throw issue("数组元素之间缺少逗号", expected: "',' 或 ']'")
            }
            skipWhitespace()
            if peek == 0x5D {
                throw issue("JSON 不允许数组末尾逗号", expected: "下一个数组元素")
            }
        }
    }

    private mutating func parseString() throws {
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x22 {
                index += 1
                return
            }
            if byte == 0x5C {
                index += 1
                guard index < bytes.count else {
                    throw issue("字符串的转义序列不完整", expected: "转义字符")
                }
                let escaped = bytes[index]
                if escaped == 0x75 {
                    for _ in 0..<4 {
                        index += 1
                        guard index < bytes.count, isHex(bytes[index]) else {
                            throw issue("Unicode 转义必须包含四位十六进制数字", expected: "十六进制数字")
                        }
                    }
                } else if ![0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(escaped) {
                    throw issue("无效的字符串转义", expected: "\\\"、\\\\、\\/、\\b、\\f、\\n、\\r、\\t 或 \\u")
                }
            } else if byte < 0x20 {
                throw issue("字符串中包含未转义的控制字符", expected: "转义后的字符")
            }
            index += 1
        }
        throw issue("字符串缺少结束双引号", expected: "'\"'")
    }

    private mutating func parseNumber() throws {
        if consume(0x2D), index == bytes.count {
            throw issue("负号后缺少数字", expected: "数字")
        }

        if consume(0x30) {
            if let byte = peek, isDigit(byte) {
                throw issue("数字不能包含前导零", expected: "小数点、指数或分隔符")
            }
        } else {
            guard let byte = peek, byte >= 0x31, byte <= 0x39 else {
                throw issue("数字格式无效", expected: "0–9")
            }
            while let byte = peek, isDigit(byte) { index += 1 }
        }

        if consume(0x2E) {
            guard let byte = peek, isDigit(byte) else {
                throw issue("小数点后缺少数字", expected: "0–9")
            }
            while let byte = peek, isDigit(byte) { index += 1 }
        }

        if peek == 0x65 || peek == 0x45 {
            index += 1
            if peek == 0x2B || peek == 0x2D { index += 1 }
            guard let byte = peek, isDigit(byte) else {
                throw issue("指数部分缺少数字", expected: "0–9")
            }
            while let byte = peek, isDigit(byte) { index += 1 }
        }
    }

    private mutating func parseLiteral(_ literal: StaticString) throws {
        let expectedBytes = Array(String(describing: literal).utf8)
        for byte in expectedBytes {
            guard index < bytes.count, bytes[index] == byte else {
                throw issue("字面量拼写错误", expected: String(describing: literal))
            }
            index += 1
        }
    }

    private mutating func enterContainer() throws {
        depth += 1
        guard depth <= 512 else {
            throw issue("JSON 嵌套超过 512 层", expected: nil)
        }
    }

    private mutating func leaveContainer() {
        depth -= 1
    }

    private mutating func skipWhitespace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private var peek: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    @discardableResult
    private mutating func consume(_ byte: UInt8) -> Bool {
        guard peek == byte else { return false }
        index += 1
        return true
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private func isHex(_ byte: UInt8) -> Bool {
        isDigit(byte) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
    }

    private func issue(_ message: String, expected: String?) -> ParseIssue {
        ParseIssue(message: message, offset: index, expected: expected)
    }
}
