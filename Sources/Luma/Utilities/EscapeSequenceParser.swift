import Foundation

enum EscapeSequenceParser {
    static func parse(_ input: String) -> String {
        var output = ""
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]
            guard character == "\\" else {
                output.append(character)
                index = input.index(after: index)
                continue
            }

            let nextIndex = input.index(after: index)
            guard nextIndex < input.endIndex else {
                output.append("\\")
                break
            }

            switch input[nextIndex] {
            case "n": output.append("\n")
            case "r": output.append("\r")
            case "t": output.append("\t")
            case "e": output.append(Character(UnicodeScalar(27)))
            case "a": output.append(Character(UnicodeScalar(7)))
            case "\\": output.append("\\")
            default:
                output.append("\\")
                output.append(input[nextIndex])
            }

            index = input.index(after: nextIndex)
        }

        return output
    }
}
