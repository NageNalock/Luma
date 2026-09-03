import Foundation

enum JSONFormattingError: Error {
    case invalid(JSONDiagnostic)
}

enum JSONTextFormatter {
    static func pretty(_ input: String, indentWidth: Int = 2) throws -> String {
        if let diagnostic = JSONDiagnosticParser.validate(input) {
            throw JSONFormattingError.invalid(diagnostic)
        }

        let characters = Array(input)
        var output = ""
        var stack: [Bool] = [] // true when the current container is empty
        var indent = 0
        var inString = false
        var escaped = false

        func nextNonWhitespace(after index: Int) -> Character? {
            guard index + 1 < characters.count else { return nil }
            for candidate in characters[(index + 1)...] where !candidate.isWhitespace {
                return candidate
            }
            return nil
        }

        func indentation(_ level: Int) -> String {
            String(repeating: " ", count: max(0, level * indentWidth))
        }

        for (index, character) in characters.enumerated() {
            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                output.append(character)
                continue
            }
            if character.isWhitespace { continue }

            switch character {
            case "{", "[":
                output.append(character)
                let closing: Character = character == "{" ? "}" : "]"
                let isEmpty = nextNonWhitespace(after: index) == closing
                stack.append(isEmpty)
                if !isEmpty {
                    indent += 1
                    output.append("\n")
                    output.append(indentation(indent))
                }
            case "}", "]":
                let isEmpty = stack.popLast() ?? false
                if !isEmpty {
                    indent -= 1
                    output.append("\n")
                    output.append(indentation(indent))
                }
                output.append(character)
            case ",":
                output.append(character)
                output.append("\n")
                output.append(indentation(indent))
            case ":":
                output.append(": ")
            default:
                output.append(character)
            }
        }

        return output
    }

    static func minified(_ input: String) throws -> String {
        if let diagnostic = JSONDiagnosticParser.validate(input) {
            throw JSONFormattingError.invalid(diagnostic)
        }

        var output = ""
        var inString = false
        var escaped = false

        for character in input {
            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                output.append(character)
            } else if !character.isWhitespace {
                output.append(character)
            }
        }

        return output
    }
}
