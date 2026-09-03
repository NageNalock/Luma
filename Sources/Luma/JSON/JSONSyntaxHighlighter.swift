import AppKit

enum JSONSyntaxHighlighter {
    static func attributedString(for source: String) -> NSAttributedString {
        let text = source as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        let result = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(red: 0.14, green: 0.14, blue: 0.17, alpha: 1)
            ]
        )

        var index = 0
        while index < text.length {
            let scalar = text.character(at: index)

            if scalar == 0x22 {
                let start = index
                index += 1
                var escaped = false
                while index < text.length {
                    let current = text.character(at: index)
                    index += 1
                    if escaped {
                        escaped = false
                    } else if current == 0x5C {
                        escaped = true
                    } else if current == 0x22 {
                        break
                    }
                }
                var lookahead = index
                while lookahead < text.length, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(text.character(at: lookahead))!) {
                    lookahead += 1
                }
                let isKey = lookahead < text.length && text.character(at: lookahead) == 0x3A
                result.addAttribute(
                    .foregroundColor,
                    value: isKey
                        ? NSColor(red: 0.39, green: 0.31, blue: 0.72, alpha: 1)
                        : NSColor(red: 0.16, green: 0.43, blue: 0.38, alpha: 1),
                    range: NSRange(location: start, length: index - start)
                )
                continue
            }

            if scalar == 0x2D || (scalar >= 0x30 && scalar <= 0x39) {
                let start = index
                index += 1
                while index < text.length {
                    let current = text.character(at: index)
                    let isNumberCharacter = (current >= 0x30 && current <= 0x39) || [0x2E, 0x45, 0x65, 0x2B, 0x2D].contains(current)
                    if !isNumberCharacter { break }
                    index += 1
                }
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor(red: 0.58, green: 0.34, blue: 0.13, alpha: 1),
                    range: NSRange(location: start, length: index - start)
                )
                continue
            }

            let remaining = text.substring(from: index)
            if let literal = ["true", "false", "null"].first(where: { remaining.hasPrefix($0) }) {
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor(red: 0.62, green: 0.24, blue: 0.40, alpha: 1),
                    range: NSRange(location: index, length: literal.utf16.count)
                )
                index += literal.utf16.count
                continue
            }

            if [0x7B, 0x7D, 0x5B, 0x5D, 0x3A, 0x2C].contains(scalar) {
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor(red: 0.44, green: 0.40, blue: 0.56, alpha: 1),
                    range: NSRange(location: index, length: 1)
                )
            }
            index += 1
        }

        result.addAttribute(.paragraphStyle, value: paragraphStyle(), range: fullRange)
        return result
    }

    private static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.tabStops = []
        style.defaultTabInterval = 24
        return style
    }
}
